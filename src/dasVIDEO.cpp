// dasVideo native module — pluggable decode backends behind one daslang surface.
//
// A VideoPlayer owns a polymorphic VideoSource (the decode backend) plus a reused
// RGBA convert buffer; the consumer borrows per-frame pixels and per-batch audio
// through `get_data` / `get_audio_data` block accessors (RAII temp views, valid
// only inside the block) — the "player owns, consumer borrows" model from
// ORIGINAL_PLAN.md. video_open probes the file and constructs the matching
// backend, so the daslang API never names the codec.
//
// Backends:
//   PlmSource  — pl_mpeg (MIT), MPEG-1 video + MP2 audio, compiled into this TU.
//   (dav1d/AV1 backend slots in beside it behind the same VideoSource — P5.)
//
// Common denominator across backends (ORIGINAL_PLAN): video = YUV 4:2:0 8-bit
// planes + pts; audio = interleaved float32 PCM + rate + pts. Audio is opt-in
// (video_enable_audio) so video-only paths stay zero-overhead; A/V sync is driven
// in das (audio is the master clock).
#include "daScript/daScript.h"
#include "daScript/ast/ast_handle.h"

#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"

#include <vector>
#include <cstring>

namespace das {

// ===== backend interface =====

// Borrowed view of the current decoded frame's native YUV 4:2:0 planes. Each plane
// is packed at its own row stride (the allocated plane width, macroblock-rounded);
// the display size is VideoSource::width()/height(). Valid until the next decode.
struct VideoFrameView {
    const uint8_t * y = nullptr, * cb = nullptr, * cr = nullptr;
    int yW = 0, yH = 0;   // Y plane stride (packed width) + height
    int cW = 0, cH = 0;   // chroma plane stride (packed width) + height
    double pts = 0.0;
};

// Borrowed view of the current decoded audio batch — interleaved float PCM. count
// is frames-per-channel, so the buffer is count*channels floats. Valid until the
// next decode.
struct AudioBatchView {
    const float * interleaved = nullptr;
    int count = 0;
    double pts = 0.0;
};

// A decode backend. One concrete impl per container/codec; video_open picks one by
// probing the file. The player drives it and borrows its current frame / audio.
struct VideoSource {
    virtual ~VideoSource() {}
    // stream info (valid right after open)
    virtual int    width() const = 0;
    virtual int    height() const = 0;
    virtual double framerate() const = 0;
    virtual int    samplerate() const = 0;
    virtual double duration() const = 0;
    virtual bool   ended() const = 0;
    // video
    virtual bool decodeVideo() = 0;                          // advance one frame; false at end of stream
    virtual bool currentFrame(VideoFrameView & v) const = 0; // borrow the current frame's planes
    // Convert the current frame to packed RGBA8 into dst at dstStride bytes/row.
    // Writes R/G/B only; the caller pre-fills the buffer opaque (alpha untouched).
    virtual void convertRgba(uint8_t * dst, int dstStride) const = 0;
    virtual void rewind() = 0;
    // audio (opt-in)
    virtual bool hasAudio() const = 0;
    virtual bool enableAudio() = 0;
    virtual int  audioChannels() const = 0;
    virtual bool decodeAudio() = 0;                          // advance one batch; false when none
    virtual bool currentAudio(AudioBatchView & a) const = 0;
};

// ===== pl_mpeg backend =====

struct PlmSource final : VideoSource {
    plm_t * plm = nullptr;
    plm_frame_t * frame = nullptr;      // current frame; borrowed from plm until next decode
    plm_samples_t * samples = nullptr;  // current audio batch; borrowed until next plm_decode_audio
    bool endedFlag = false;

    // Try to open filename as an MPEG-1 stream; null if pl_mpeg can't (lets
    // video_open fall through to another backend).
    static PlmSource * tryOpen(const char * filename) {
        plm_t * plm = plm_create_with_filename(filename);
        if ( !plm ) return nullptr;
        plm_set_audio_enabled(plm, 0);  // audio is opt-in (video_enable_audio)
        auto * s = new PlmSource();
        s->plm = plm;
        return s;
    }
    ~PlmSource() override { if ( plm ) plm_destroy(plm); }

    int    width() const override      { return plm ? plm_get_width(plm) : 0; }
    int    height() const override     { return plm ? plm_get_height(plm) : 0; }
    double framerate() const override  { return plm ? plm_get_framerate(plm) : 0.0; }
    int    samplerate() const override { return plm ? plm_get_samplerate(plm) : 0; }
    double duration() const override   { return plm ? plm_get_duration(plm) : 0.0; }
    bool   ended() const override      { return !plm ? true : (endedFlag || plm_has_ended(plm) != 0); }

    bool decodeVideo() override {
        if ( !plm ) return false;
        frame = plm_decode_video(plm);
        if ( !frame ) { endedFlag = true; return false; }
        return true;
    }
    bool currentFrame(VideoFrameView & v) const override {
        if ( !frame ) return false;
        v.y  = frame->y.data;  v.yW = int(frame->y.width);  v.yH = int(frame->y.height);
        v.cb = frame->cb.data; v.cr = frame->cr.data;
        v.cW = int(frame->cb.width); v.cH = int(frame->cb.height);
        v.pts = frame->time;
        return true;
    }
    void convertRgba(uint8_t * dst, int dstStride) const override {
        if ( frame ) plm_frame_to_rgba(frame, dst, dstStride);
    }
    void rewind() override {
        if ( !plm ) return;
        plm_rewind(plm);
        endedFlag = false; frame = nullptr; samples = nullptr;
    }
    bool hasAudio() const override { return plm ? plm_get_num_audio_streams(plm) > 0 : false; }
    bool enableAudio() override {
        if ( !plm || plm_get_num_audio_streams(plm) <= 0 ) return false;
        plm_set_audio_stream(plm, 0);
        plm_set_audio_enabled(plm, 1);
        return true;
    }
    int audioChannels() const override { return 2; }  // pl_mpeg always decodes interleaved stereo
    bool decodeAudio() override {
        if ( !plm ) return false;
        samples = plm_decode_audio(plm);
        return samples != nullptr;
    }
    bool currentAudio(AudioBatchView & a) const override {
        if ( !samples ) return false;
        a.interleaved = samples->interleaved;
        a.count = int(samples->count);
        a.pts = samples->time;
        return true;
    }
};

// Format dispatch. P5+ probes magic bytes here (AV1/WebM) and returns the matching
// backend; for now pl_mpeg is the only one.
static VideoSource * createSourceFor(const char * filename) {
    return PlmSource::tryOpen(filename);
}

// ===== player (backend-agnostic) =====

struct VideoPlayer {
    VideoSource * src = nullptr;
    std::vector<uint8_t> rgba;   // player-owned RGBA convert target, reused per frame
};

}

MAKE_TYPE_FACTORY(VideoPlayer, das::VideoPlayer)

namespace das {

// ===== lifecycle =====

static VideoPlayer * video_open(const char * filename) {
    if ( !filename || !*filename ) return nullptr;
    VideoSource * src = createSourceFor(filename);
    if ( !src ) return nullptr;
    auto * p = new VideoPlayer();
    p->src = src;
    return p;
}

static void video_close(VideoPlayer * p) {
    if ( !p ) return;
    delete p->src;
    delete p;
}

// ===== info =====

static int32_t video_width(VideoPlayer * p)      { return (p && p->src) ? p->src->width() : 0; }
static int32_t video_height(VideoPlayer * p)     { return (p && p->src) ? p->src->height() : 0; }
static double  video_framerate(VideoPlayer * p)  { return (p && p->src) ? p->src->framerate() : 0.0; }
static int32_t video_samplerate(VideoPlayer * p) { return (p && p->src) ? p->src->samplerate() : 0; }
static double  video_duration(VideoPlayer * p)   { return (p && p->src) ? p->src->duration() : 0.0; }
static bool    video_has_ended(VideoPlayer * p)  { return (p && p->src) ? p->src->ended() : true; }

static double video_frame_time(VideoPlayer * p) {
    VideoFrameView v;
    return (p && p->src && p->src->currentFrame(v)) ? v.pts : 0.0;
}
// Plane strides (== tightly-packed plane widths, macroblock-rounded) for the YUV
// route; display size is video_width/height.
static int32_t video_y_stride(VideoPlayer * p) {
    VideoFrameView v;
    return (p && p->src && p->src->currentFrame(v)) ? v.yW : 0;
}
static int32_t video_uv_stride(VideoPlayer * p) {
    VideoFrameView v;
    return (p && p->src && p->src->currentFrame(v)) ? v.cW : 0;
}

// ===== decode =====

// Decode the next video frame. Returns true if a frame was produced, false at end
// of stream. The frame is held by the player until the next decode call.
static bool video_decode(VideoPlayer * p) {
    return (p && p->src) ? p->src->decodeVideo() : false;
}

// Rewind to the start (for looping playback).
static void video_rewind(VideoPlayer * p) {
    if ( p && p->src ) p->src->rewind();
}

// ===== audio (opt-in) =====

static bool video_has_audio(VideoPlayer * p) {
    return (p && p->src) ? p->src->hasAudio() : false;
}

// Enable the (first) audio stream. video_open leaves audio disabled so the
// video-only paths never buffer audio packets; call this right after open if you
// want sound. Returns true only if the file actually has an audio stream.
static bool video_enable_audio(VideoPlayer * p) {
    return (p && p->src) ? p->src->enableAudio() : false;
}

static int32_t video_audio_channels(VideoPlayer * p) {
    return (p && p->src) ? p->src->audioChannels() : 0;
}

// Decode the next audio batch. Returns true if a batch was produced; held by the
// player until the next call.
static bool video_decode_audio(VideoPlayer * p) {
    return (p && p->src) ? p->src->decodeAudio() : false;
}

static double video_audio_time(VideoPlayer * p) {
    AudioBatchView a;
    return (p && p->src && p->src->currentAudio(a)) ? a.pts : 0.0;
}
static int32_t video_audio_count(VideoPlayer * p) {  // frames per channel
    AudioBatchView a;
    return (p && p->src && p->src->currentAudio(a)) ? a.count : 0;
}

// Borrowed audio access: hand the decoded interleaved floats (count*channels) to
// the block, valid only inside it. append_to_pcm takes ownership, so clone the
// borrowed samples into a real array before pushing them.
static void video_get_audio_data(VideoPlayer * p,
        const TBlock<void, TTemporary<TArray<float> const>> & block,
        Context * context, LineInfoArg * at) {
    AudioBatchView a;
    if ( !p || !p->src || !p->src->currentAudio(a) ) return;
    Array arr;
    array_mark_locked(arr, (void *)a.interleaved, uint64_t(a.count) * uint64_t(p->src->audioChannels()));
    vec4f args[1];
    args[0] = cast<Array *>::from(&arr);
    context->invoke(block, args, nullptr, at);
}

// ===== borrowed pixel access (player owns, consumer borrows) =====

// Easy route: convert the current frame to packed RGBA8 into the player-owned
// buffer, hand a borrowed view to the block (valid only inside the block).
static void video_get_data_rgba(VideoPlayer * p,
        const TBlock<void, TTemporary<TArray<uint8_t> const>> & block,
        Context * context, LineInfoArg * at) {
    VideoFrameView v;
    if ( !p || !p->src || !p->src->currentFrame(v) ) return;
    const int w = p->src->width(), h = p->src->height();
    const size_t need = size_t(w) * size_t(h) * 4;
    if ( p->rgba.size() != need ) {
        p->rgba.resize(need);
        // convertRgba writes R/G/B but never the alpha byte; fill 0xFF once per
        // (re)alloc so frames are opaque. The convert overwrites only RGB, so alpha
        // stays 0xFF across frames — no need to refill every frame.
        memset(p->rgba.data(), 0xFF, p->rgba.size());
    }
    p->src->convertRgba(p->rgba.data(), w * 4);
    Array arr;
    array_mark_locked(arr, p->rgba.data(), uint64_t(p->rgba.size()));
    vec4f args[1];
    args[0] = cast<Array *>::from(&arr);
    context->invoke(block, args, nullptr, at);
}

// Advanced route: hand the native YUV420p planes (Y, U=cb, V=cr) to the block,
// zero-copy. Each plane is tightly packed at its stride (video_y_stride /
// video_uv_stride); the display size is video_width/height. Valid only inside the block.
static void video_get_data_yuv(VideoPlayer * p,
        const TBlock<void, TTemporary<TArray<uint8_t> const>, TTemporary<TArray<uint8_t> const>, TTemporary<TArray<uint8_t> const>> & block,
        Context * context, LineInfoArg * at) {
    VideoFrameView v;
    if ( !p || !p->src || !p->src->currentFrame(v) ) return;
    Array ay, au, av;
    array_mark_locked(ay, (void *)v.y,  uint64_t(v.yW) * uint64_t(v.yH));
    array_mark_locked(au, (void *)v.cb, uint64_t(v.cW) * uint64_t(v.cH));
    array_mark_locked(av, (void *)v.cr, uint64_t(v.cW) * uint64_t(v.cH));
    vec4f args[3];
    args[0] = cast<Array *>::from(&ay);
    args[1] = cast<Array *>::from(&au);
    args[2] = cast<Array *>::from(&av);
    context->invoke(block, args, nullptr, at);
}

// P0 probe (kept for the headless smoke): proves the module loaded + linked.
static int32_t video_backend_ready() {
    return 1;
}

class Module_dasVIDEO : public Module {
public:
    Module_dasVIDEO() : Module("video") {
        ModuleLibrary lib(this);
        lib.addBuiltInModule();
        // Opaque handle: das holds a VideoPlayer? pointer; lifetime is explicit
        // (video_open / video_close). No fields exposed.
        addAnnotation(new DummyTypeAnnotation("VideoPlayer", "das::VideoPlayer",
            sizeof(VideoPlayer), alignof(VideoPlayer)));
        addExtern<DAS_BIND_FUN(video_open)>(*this, lib, "video_open",
            SideEffects::modifyExternal, "video_open")->args({"filename"});
        addExtern<DAS_BIND_FUN(video_close)>(*this, lib, "video_close",
            SideEffects::modifyExternal, "video_close")->args({"player"});
        addExtern<DAS_BIND_FUN(video_decode)>(*this, lib, "video_decode",
            SideEffects::modifyExternal, "video_decode")->args({"player"});
        addExtern<DAS_BIND_FUN(video_rewind)>(*this, lib, "video_rewind",
            SideEffects::modifyExternal, "video_rewind")->args({"player"});
        addExtern<DAS_BIND_FUN(video_width)>(*this, lib, "video_width",
            SideEffects::none, "video_width")->args({"player"});
        addExtern<DAS_BIND_FUN(video_height)>(*this, lib, "video_height",
            SideEffects::none, "video_height")->args({"player"});
        addExtern<DAS_BIND_FUN(video_framerate)>(*this, lib, "video_framerate",
            SideEffects::none, "video_framerate")->args({"player"});
        addExtern<DAS_BIND_FUN(video_samplerate)>(*this, lib, "video_samplerate",
            SideEffects::none, "video_samplerate")->args({"player"});
        addExtern<DAS_BIND_FUN(video_duration)>(*this, lib, "video_duration",
            SideEffects::none, "video_duration")->args({"player"});
        addExtern<DAS_BIND_FUN(video_frame_time)>(*this, lib, "video_frame_time",
            SideEffects::none, "video_frame_time")->args({"player"});
        addExtern<DAS_BIND_FUN(video_has_ended)>(*this, lib, "video_has_ended",
            SideEffects::none, "video_has_ended")->args({"player"});
        addExtern<DAS_BIND_FUN(video_y_stride)>(*this, lib, "video_y_stride",
            SideEffects::none, "video_y_stride")->args({"player"});
        addExtern<DAS_BIND_FUN(video_uv_stride)>(*this, lib, "video_uv_stride",
            SideEffects::none, "video_uv_stride")->args({"player"});
        addExtern<DAS_BIND_FUN(video_get_data_rgba)>(*this, lib, "get_data",
            SideEffects::modifyExternal, "video_get_data_rgba")->args({"player","block","context","line"});
        addExtern<DAS_BIND_FUN(video_get_data_yuv)>(*this, lib, "get_data",
            SideEffects::modifyExternal, "video_get_data_yuv")->args({"player","block","context","line"});
        // audio (opt-in)
        addExtern<DAS_BIND_FUN(video_has_audio)>(*this, lib, "video_has_audio",
            SideEffects::none, "video_has_audio")->args({"player"});
        addExtern<DAS_BIND_FUN(video_enable_audio)>(*this, lib, "video_enable_audio",
            SideEffects::modifyExternal, "video_enable_audio")->args({"player"});
        addExtern<DAS_BIND_FUN(video_audio_channels)>(*this, lib, "video_audio_channels",
            SideEffects::none, "video_audio_channels")->args({"player"});
        addExtern<DAS_BIND_FUN(video_decode_audio)>(*this, lib, "video_decode_audio",
            SideEffects::modifyExternal, "video_decode_audio")->args({"player"});
        addExtern<DAS_BIND_FUN(video_audio_time)>(*this, lib, "video_audio_time",
            SideEffects::none, "video_audio_time")->args({"player"});
        addExtern<DAS_BIND_FUN(video_audio_count)>(*this, lib, "video_audio_count",
            SideEffects::none, "video_audio_count")->args({"player"});
        addExtern<DAS_BIND_FUN(video_get_audio_data)>(*this, lib, "get_audio_data",
            SideEffects::modifyExternal, "video_get_audio_data")->args({"player","block","context","line"});
        addExtern<DAS_BIND_FUN(video_backend_ready)>(*this, lib, "video_backend_ready",
            SideEffects::none, "video_backend_ready");
        verifyAotReady();
    }
};

REGISTER_DYN_MODULE(Module_dasVIDEO, Module_dasVIDEO);

}

REGISTER_MODULE_IN_NAMESPACE(Module_dasVIDEO, das)
