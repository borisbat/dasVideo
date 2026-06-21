options gen2

// Self-verifying gate for tutorial 04. Decodes one frame of the bundled sample and
// checks the native YUV420p plane shapes the GPU path relies on: Y is full-res, U/V
// are quarter-res, each packed at its own (macroblock-rounded) stride. Headless.

require video
require daslib/defer

[export]
def main() {
    var p = video_open("tutorials/04_yuv_shader/sample.mpg")
    verify(p != null, "the sample opens")
    defer() { video_close(p) }
    verify(video_decode(p), "decodes a frame")
    let h = video_height(p)
    p |> get_data() $(y, u, v : array<uint8>#) {
        verify(length(y) == video_y_stride(p) * h, "Y plane is y_stride x height (full-res)")
        verify(length(u) == video_uv_stride(p) * (h / 2), "U plane is uv_stride x height/2 (quarter-res)")
        verify(length(v) == length(u), "V plane matches U")
    }
    print("tutorial 04 ok: {video_width(p)}x{h}, y_stride {video_y_stride(p)}, uv_stride {video_uv_stride(p)}\n")
}
