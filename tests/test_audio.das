options gen2

require video
require math

// P3 headless audio-decode test: open the MPEG-1 fixture that carries an MP2
// audio track, enable audio, and decode every batch through the get_audio_data
// borrow. No audio device — this exercises the decode + borrow path only (the
// real-playback path, which needs a device, is verified by the example locally).
// Run from the repo root:
//   daslang -load_module <repo> tests/test_audio.das
[export]
def main() {
    // the video-only fixture must report no audio, and enabling must fail cleanly
    var silent = video_open("tests/fixtures/test.mpg")
    verify(silent != null, "video_open (silent fixture) should succeed")
    verify(!video_has_audio(silent), "test.mpg has no audio stream")
    verify(!video_enable_audio(silent), "enabling audio on a silent file returns false")
    video_close(silent)

    var p = video_open("tests/fixtures/test_audio.mpg")
    verify(p != null, "video_open (audio fixture) should succeed")
    verify(video_has_audio(p), "test_audio.mpg has an audio stream")
    verify(video_enable_audio(p), "enabling audio succeeds")
    verify(video_samplerate(p) == 44100, "audio sample rate is 44100")
    verify(video_audio_channels(p) == 2, "pl_mpeg audio is stereo")

    var batches = 0
    var last_time = -1.0lf
    var peak = 0.0
    while (video_decode_audio(p)) {
        let count = video_audio_count(p)
        verify(count == 1152, "each MP2 batch is 1152 stereo frames")
        let t = video_audio_time(p)
        verify(t > last_time, "audio batch time advances monotonically")
        last_time = t
        p |> get_audio_data() $(s : array<float>#) {
            verify(length(s) == count * 2, "borrowed buffer is count*2 interleaved floats")
            for (v in s) {
                peak = max(peak, abs(v))
            }
        }
        batches++
    }
    // ~2s at 44100 / 1152 ≈ 76 batches; require a healthy lower bound
    verify(batches >= 60, "should decode the whole ~2s audio track")
    // the fixture is a 440Hz sine — real decoded audio has substantial amplitude
    verify(peak > 0.1, "decoded audio is non-trivial (sine peak well above noise)")
    verify(peak <= 2.0, "decoded audio is normalized (no garbage out-of-range samples)")

    video_close(p)
    print("dasVideo P3: decoded {batches} audio batches, peak amplitude {peak}\n")
}
