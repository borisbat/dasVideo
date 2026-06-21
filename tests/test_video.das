options gen2

require video

// P1 headless decode test: open the MPEG-1 fixture, decode every frame, and
// exercise both get_data routes (packed RGBA + native YUV planes). No GPU /
// display / audio. Run from the repo root:
//   daslang -load_module <repo> tests/test_video.das
[export]
def main() {
    var p = video_open("tests/fixtures/test.mpg")
    verify(p != null, "video_open should succeed")
    verify(video_width(p) == 64, "width should be 64")
    verify(video_height(p) == 48, "height should be 48")

    var frames = 0
    var rgba_checksum = 0u
    var yuv_seen = false
    while (video_decode(p)) {
        frames++
        p |> get_data() $(rgb : array<uint8>#) {
            verify(length(rgb) == 64 * 48 * 4, "RGBA buffer is width*height*4")
            verify(rgb[3] == 255u, "RGBA frames are opaque (alpha = 255)")
            for (b in rgb) {
                rgba_checksum += uint(b)
            }
        }
        if (!yuv_seen) {
            p |> get_data() $(y, u, v : array<uint8>#) {
                verify(length(y) == 64 * 48, "Y plane is full-res")
                verify(length(u) == 32 * 24, "U plane is quarter-res")
                verify(length(v) == 32 * 24, "V plane is quarter-res")
            }
            yuv_seen = true
        }
    }
    verify(frames > 0, "should decode at least one frame")
    verify(rgba_checksum > 0u, "decoded pixels should be non-zero")
    video_close(p)
    print("dasVideo P1: decoded {frames} frames, rgba checksum {rgba_checksum}\n")
}
