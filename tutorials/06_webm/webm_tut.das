options gen2

// Tutorial 06 — One API, many containers (AV1 in WebM, with Opus sound).
//
// Everything so far played MPEG-1. The same code plays AV1 too — as a raw `.ivf`
// elementary stream, or inside a WebM container alongside Opus audio. `video_open`
// sniffs the file's magic bytes and picks the backend (pl_mpeg / dav1d / nestegg +
// dav1d + libopus); your code never names the codec. Open, decode, borrow — the
// surface is identical to the MPEG-1 tutorials.
//
// This file is a library; the runnable is its test, `test_webm_decode.das`.

require video
require daslib/defer
require math

struct MediaProbe {
    width, height  : int
    has_audio      : bool
    samplerate     : int
    audio_channels : int
    video_frames   : int
    audio_batches  : int
    audio_peak     : float
}

// Open `path` (format auto-detected), decode the whole stream, and report what came
// out — proving the WebM / AV1 / Opus path runs through the exact same surface as
// the MPEG-1 tutorials. Audio is opt-in, so enable it when the file has a track.
def public probe_media(path : string) : MediaProbe {
    var p = video_open(path)
    if (p == null) return MediaProbe()
    defer() { video_close(p) }
    var m = MediaProbe(width = video_width(p), height = video_height(p),
        has_audio = video_has_audio(p))
    if (m.has_audio && video_enable_audio(p)) {
        m.samplerate = video_samplerate(p)
        m.audio_channels = video_audio_channels(p)
    }
    // Decode the AV1 video frames. dav1d does the work; `get_data` would borrow the
    // pixels exactly as in tutorial 02 — here we just count them.
    while (video_decode(p)) {
        m.video_frames++
    }
    // Decode the Opus audio. libopus hands back interleaved float PCM through the
    // same `get_audio_data` borrow as the MP2 audio in tutorial 05.
    while (video_decode_audio(p)) {
        m.audio_batches++
        p |> get_audio_data() $(s : array<float>#) {
            for (v in s) {
                m.audio_peak = max(m.audio_peak, abs(v))
            }
        }
    }
    return m
}
