options gen2

require video
require math

// P5.2 headless decode test: open the WebM fixture (AV1 video + Opus audio). The
// EBML magic (0x1A45DFA3) routes video_open to the WebM backend automatically —
// nestegg demuxes the container, dav1d decodes the AV1 video, libopus decodes the
// Opus audio. The daslang API is identical to the MPEG-1 / IVF paths. No GPU /
// display. Run from the repo root:
//   daslang -load_module <repo> tests/test_webm.das
[export]
def main() {
    var p = video_open("tests/fixtures/test.webm")
    verify(p != null, "video_open should open the WebM (AV1+Opus) file")
    verify(video_width(p) == 64, "width should be 64")
    verify(video_height(p) == 48, "height should be 48")

    // audio is opt-in and must be enabled before draining the container, or the
    // interleaved Opus packets are dropped while the video is decoded.
    verify(video_has_audio(p), "test.webm carries an Opus audio stream")
    verify(video_enable_audio(p), "enabling audio succeeds")
    verify(video_samplerate(p) == 48000, "Opus decodes at 48000 Hz")
    verify(video_audio_channels(p) == 2, "fixture audio is stereo")

    // decode every video frame through both get_data routes (packed RGBA + native
    // YUV planes). dav1d aligns plane strides, so size the borrowed planes against
    // the reported strides, exactly as the IVF path does.
    var frames = 0
    var rgba_checksum = 0u
    var yuv_seen = false
    while (video_decode(p)) {
        frames++
        p |> get_data() $(rgb : array<uint8>#) {
            verify(length(rgb) == 64 * 48 * 4, "RGBA buffer is width*height*4")
            verify(rgb[3] == 255u8, "RGBA frames are opaque (alpha = 255)")
            for (b in rgb) {
                rgba_checksum += uint(b)
            }
        }
        if (!yuv_seen) {
            p |> get_data() $(y, u, v : array<uint8>#) {
                verify(length(y) == video_y_stride(p) * video_height(p), "Y plane is y_stride*height")
                verify(video_y_stride(p) >= 64, "Y stride covers the display width")
                verify(length(u) == video_uv_stride(p) * ((video_height(p) + 1) / 2), "U plane is uv_stride*chroma_height")
                verify(length(v) == length(u), "V plane matches U")
            }
            yuv_seen = true
        }
    }
    verify(frames > 0, "should decode at least one AV1 frame from the WebM")
    verify(rgba_checksum > 0u, "decoded pixels should be non-zero")

    // the Opus packets were queued during the video drain; decode them all now.
    var batches = 0
    var total_samples = 0
    var peak = 0.0
    var last_time = -1.0lf
    while (video_decode_audio(p)) {
        let count = video_audio_count(p)
        verify(count > 0, "each Opus batch decodes a positive sample count")
        total_samples += count
        let t = video_audio_time(p)
        verify(t >= last_time, "audio batch time advances")
        last_time = t
        p |> get_audio_data() $(s : array<float>#) {
            verify(length(s) == count * 2, "borrowed buffer is count*2 interleaved floats")
            for (v in s) {
                peak = max(peak, abs(v))
            }
        }
        batches++
    }
    verify(batches > 0, "should decode at least one Opus batch")
    // ~2s @ 48000 Hz ≈ 96000 frames per channel; require a healthy lower bound
    verify(total_samples >= 80000, "should decode close to the whole ~2s audio track")
    // the fixture is a loud 440Hz sine — real decoded audio has substantial amplitude
    verify(peak > 0.1, "decoded audio is non-trivial (sine peak well above noise)")
    verify(peak <= 2.0, "decoded audio is normalized (no garbage out-of-range samples)")

    // video_rewind on the WebM backend = nestegg_track_seek(0) + dav1d_flush; the
    // whole video stream then decodes again from the start.
    video_rewind(p)
    var replayed = 0
    while (video_decode(p)) {
        replayed++
    }
    verify(replayed == frames, "video_rewind replays the full WebM video stream")

    video_close(p)
    print("dasVideo P5.2: decoded {frames} AV1 frames + {batches} Opus batches ({total_samples} samples/ch) from WebM, rgba checksum {rgba_checksum}\n")
}
