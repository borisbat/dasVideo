options gen2

require video

// P5.1 headless decode test: open the AV1 IVF fixture. The "DKIF" magic routes
// video_open to the dav1d backend automatically — the daslang API is identical to
// the MPEG-1 path. Decode every frame and exercise both get_data routes (packed
// RGBA + native YUV planes). No GPU / display. Run from the repo root:
//   daslang -load_module <repo> tests/test_av1.das
[export]
def main() {
    var p = video_open("tests/fixtures/test_av1.ivf")
    verify(p != null, "video_open should open the AV1 IVF")
    verify(video_width(p) == 64, "width should be 64")
    verify(video_height(p) == 48, "height should be 48")

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
                // dav1d aligns plane strides (they may exceed the display width), so
                // size the borrowed planes against the reported strides.
                verify(length(y) == video_y_stride(p) * video_height(p), "Y plane is y_stride*height")
                verify(video_y_stride(p) >= 64, "Y stride covers the display width")
                verify(length(u) == video_uv_stride(p) * ((video_height(p) + 1) / 2), "U plane is uv_stride*chroma_height")
                verify(length(v) == length(u), "V plane matches U")
            }
            yuv_seen = true
        }
    }
    verify(frames > 0, "should decode at least one AV1 frame")
    verify(rgba_checksum > 0u, "decoded pixels should be non-zero")

    // video_rewind on the dav1d backend = fseek to the first packet + dav1d_flush;
    // the whole stream then decodes again from the start.
    video_rewind(p)
    var replayed = 0
    while (video_decode(p)) {
        replayed++
    }
    verify(replayed == frames, "video_rewind replays the full AV1 stream")

    video_close(p)
    print("dasVideo P5.1: decoded {frames} AV1 frames via dav1d, rgba checksum {rgba_checksum}\n")
}
