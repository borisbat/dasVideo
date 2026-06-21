// dasVideo native module — P1: pl_mpeg video decode.
//
// Opens an MPEG-1 (.mpg) stream and decodes video frames. pl_mpeg (MIT) is
// compiled into this TU. The player owns the decoder + a reused RGBA convert
// buffer; the consumer borrows per-frame pixels through `get_data` block
// accessors (RAII temp views, valid only inside the block) — the "player owns,
// consumer borrows" model from ORIGINAL_PLAN.md. Audio + A/V sync are P3.
#include "daScript/daScript.h"
#include "daScript/ast/ast_handle.h"

#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"

#include <vector>
#include <cstring>

namespace das {

struct VideoPlayer {
    plm_t * plm = nullptr;
    plm_frame_t * frame = nullptr;      // last decoded frame; borrowed from plm, valid until next decode
    std::vector<uint8_t> rgba;          // player-owned RGBA convert target, reused per frame
    bool ended = false;
};

}

MAKE_TYPE_FACTORY(VideoPlayer, das::VideoPlayer)

namespace das {

// ===== lifecycle =====

static VideoPlayer * video_open(const char * filename) {
    if ( !filename || !*filename ) return nullptr;
    plm_t * plm = plm_create_with_filename(filename);
    if ( !plm ) return nullptr;
    plm_set_audio_enabled(plm, 0);      // P1: video only; audio is P3
    auto * p = new VideoPlayer();
    p->plm = plm;
    return p;
}

static void video_close(VideoPlayer * p) {
    if ( !p ) return;
    if ( p->plm ) plm_destroy(p->plm);
    delete p;
}

// ===== info =====

static int32_t video_width(VideoPlayer * p)      { return (p && p->plm) ? plm_get_width(p->plm) : 0; }
static int32_t video_height(VideoPlayer * p)     { return (p && p->plm) ? plm_get_height(p->plm) : 0; }
static double  video_framerate(VideoPlayer * p)  { return (p && p->plm) ? plm_get_framerate(p->plm) : 0.0; }
static int32_t video_samplerate(VideoPlayer * p) { return (p && p->plm) ? plm_get_samplerate(p->plm) : 0; }
static double  video_duration(VideoPlayer * p)   { return (p && p->plm) ? plm_get_duration(p->plm) : 0.0; }
static double  video_frame_time(VideoPlayer * p) { return (p && p->frame) ? p->frame->time : 0.0; }
static bool    video_has_ended(VideoPlayer * p)  { return (!p || !p->plm) ? true : (p->ended || plm_has_ended(p->plm) != 0); }

// Plane strides (== tightly-packed plane widths, macroblock-rounded) for the YUV
// route; display size is video_width/height.
static int32_t video_y_stride(VideoPlayer * p)   { return (p && p->frame) ? int32_t(p->frame->y.width)  : 0; }
static int32_t video_uv_stride(VideoPlayer * p)  { return (p && p->frame) ? int32_t(p->frame->cb.width) : 0; }

// ===== decode =====

// Decode the next video frame. Returns true if a frame was produced, false at
// end of stream. The frame is held by the player until the next decode call.
static bool video_decode(VideoPlayer * p) {
    if ( !p || !p->plm ) return false;
    p->frame = plm_decode_video(p->plm);
    if ( !p->frame ) { p->ended = true; return false; }
    return true;
}

// Rewind to the start (for looping playback).
static void video_rewind(VideoPlayer * p) {
    if ( !p || !p->plm ) return;
    plm_rewind(p->plm);
    p->ended = false;
    p->frame = nullptr;
}

// ===== borrowed pixel access (player owns, consumer borrows) =====

// Easy route: convert the current frame to packed RGBA8 into the player-owned
// buffer, hand a borrowed view to the block (valid only inside the block).
static void video_get_data_rgba(VideoPlayer * p,
        const TBlock<void, TTemporary<TArray<uint8_t> const>> & block,
        Context * context, LineInfoArg * at) {
    if ( !p || !p->frame ) return;
    const size_t need = size_t(p->frame->width) * p->frame->height * 4;
    if ( p->rgba.size() != need ) {
        p->rgba.resize(need);
        // plm_frame_to_rgba writes R/G/B but never the alpha byte; fill 0xFF once
        // per (re)alloc so frames are opaque. The convert overwrites only RGB, so
        // alpha stays 0xFF across frames — no need to refill every frame.
        memset(p->rgba.data(), 0xFF, p->rgba.size());
    }
    plm_frame_to_rgba(p->frame, p->rgba.data(), int(p->frame->width) * 4);
    Array arr;
    array_mark_locked(arr, p->rgba.data(), uint64_t(p->rgba.size()));
    vec4f args[1];
    args[0] = cast<Array *>::from(&arr);
    context->invoke(block, args, nullptr, at);
}

// Advanced route: hand the native YUV420p planes (Y, U=cb, V=cr) to the block,
// zero-copy. Each plane is tightly packed at its plane.width (the stride); the
// display size is video_width/height. Valid only inside the block.
static void video_get_data_yuv(VideoPlayer * p,
        const TBlock<void, TTemporary<TArray<uint8_t> const>, TTemporary<TArray<uint8_t> const>, TTemporary<TArray<uint8_t> const>> & block,
        Context * context, LineInfoArg * at) {
    if ( !p || !p->frame ) return;
    Array ay, au, av;
    array_mark_locked(ay, p->frame->y.data,  uint64_t(p->frame->y.width)  * p->frame->y.height);
    array_mark_locked(au, p->frame->cb.data, uint64_t(p->frame->cb.width) * p->frame->cb.height);
    array_mark_locked(av, p->frame->cr.data, uint64_t(p->frame->cr.width) * p->frame->cr.height);
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
        addExtern<DAS_BIND_FUN(video_backend_ready)>(*this, lib, "video_backend_ready",
            SideEffects::none, "video_backend_ready");
        verifyAotReady();
    }
};

REGISTER_DYN_MODULE(Module_dasVIDEO, Module_dasVIDEO);

}

REGISTER_MODULE_IN_NAMESPACE(Module_dasVIDEO, das);
