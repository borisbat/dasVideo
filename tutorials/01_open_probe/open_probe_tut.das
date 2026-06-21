options gen2

// Tutorial 01 — Open and probe a video.
//
// The smallest useful dasVideo step: open an MPEG-1 file and read back what it is
// — size, frame rate, duration, and whether it carries an audio track. No decoding
// yet, no window; just the handle and the info getters. This is the foundation
// every later tutorial builds on.
//
// This file is a library (it exports `probe_video`); the runnable is its self-
// verifying test, `test_open_probe.das`.

require video
require daslib/defer

// A plain, copyable snapshot of a clip's stream info. `ok` is false if the file
// couldn't be opened — the caller checks it before trusting the other fields.
struct VideoInfo {
    ok         : bool
    width      : int
    height     : int
    framerate  : double
    duration   : double
    has_audio  : bool
    samplerate : int
}

// Open `path`, read its info, and close it again. video_open returns null on
// failure; the defer guarantees video_close runs no matter how we leave the
// function — the canonical open/close idiom.
def public probe_video(path : string) : VideoInfo {
    var player = video_open(path)
    if (player == null) return VideoInfo()
    defer() { video_close(player) }
    return VideoInfo(
        ok = true,
        width = video_width(player),
        height = video_height(player),
        framerate = video_framerate(player),
        duration = video_duration(player),
        has_audio = video_has_audio(player),
        samplerate = video_samplerate(player))
}
