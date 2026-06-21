options gen2

// Self-verifying gate for tutorial 05. Enables the audio track, decodes every MP2
// batch through the get_audio_data borrow, and checks the batch shape + that the
// samples are real (non-trivial amplitude). Device-free: this covers the decode +
// borrow path; the actual synced playback is what you watch in the recording.

require video
require daslib/defer
require math

[export]
def main() {
    var p = video_open("tutorials/05_audio_sync/sample.mpg")
    verify(p != null, "the sample opens")
    defer() { video_close(p) }
    verify(video_has_audio(p), "the sample has an audio track")
    verify(video_enable_audio(p), "enabling audio succeeds")
    verify(video_audio_channels(p) == 2, "pl_mpeg audio is interleaved stereo")
    var batches = 0
    var peak = 0.0
    while (video_decode_audio(p)) {
        let count = video_audio_count(p)
        verify(count == 1152, "each MP2 batch is 1152 stereo frames")
        p |> get_audio_data() $(s : array<float>#) {
            verify(length(s) == count * 2, "borrowed buffer is count*2 interleaved floats")
            for (v in s) {
                peak = max(peak, abs(v))
            }
        }
        batches++
    }
    verify(batches >= 60, "decodes the whole ~2s audio track")
    verify(peak > 0.1, "decoded audio is real (non-trivial amplitude)")
    print("tutorial 05 ok: {batches} audio batches, peak {peak}\n")
}
