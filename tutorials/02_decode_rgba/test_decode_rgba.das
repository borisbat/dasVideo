options gen2

// Self-verifying gate for tutorial 02. Decodes the bundled sample (an ffmpeg
// testsrc 64x48 clip, 25 frames, no audio) through the RGBA borrow and checks
// the frame count, that pixels are non-zero and opaque, and that video_rewind
// replays the whole stream. Headless — no display.

require decode_rgba_tut

[export]
def main() {
    let st = decode_stats("tutorials/02_decode_rgba/sample.mpg")
    verify(st.frames == 25, "the sample decodes to 25 frames")
    verify(st.checksum > 0u, "decoded pixels are non-zero")
    verify(st.opaque, "RGBA frames are opaque (alpha 255)")
    verify(replay_count("tutorials/02_decode_rgba/sample.mpg") == st.frames,
        "video_rewind replays the full stream")
    print("tutorial 02 ok: decoded {st.frames} frames, checksum {st.checksum}\n")
}
