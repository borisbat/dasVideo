options gen2

// Self-verifying gate for tutorial 01. Probes the bundled sample clip and checks
// the reported info against its known shape (ffmpeg testsrc 64x48 + a 44100 Hz
// tone). Runs headless — no display, no audio device.
//
//   daslang -load_module <repo> tutorials/01_open_probe/test_open_probe.das

require open_probe_tut

[export]
def main() {
    let info = probe_video("tutorials/01_open_probe/sample.mpg")
    verify(info.ok, "the sample clip opens")
    verify(info.width == 64, "width is 64")
    verify(info.height == 48, "height is 48")
    verify(info.duration > 0.0lf, "duration is positive")
    verify(info.has_audio, "the sample has an audio track")
    verify(info.samplerate == 44100, "audio is 44100 Hz")
    print("tutorial 01 ok: {info.width}x{info.height} @ {info.framerate} fps, {info.duration} s, audio {info.samplerate} Hz\n")
}
