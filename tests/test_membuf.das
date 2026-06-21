options gen2

require video
require daslib/fio

// P5.1 play-from-memory: read a clip into an array<uint8> and open it from that
// borrowed buffer (zero-copy — video_open references the bytes, which stay alive
// for the whole open/decode/close below). Same auto-detection as the file path, so
// both the MPEG-1 and AV1 backends are exercised. Run from the repo root:
//   daslang -load_module <repo> tests/test_membuf.das
def private decode_from_memory(path : string) : int {
    let sz = int(stat(path).size)
    verify(sz > 0, "fixture exists and is non-empty")
    var frames = 0
    fopen(path, "rb") $(f : file) {
        fload(f, sz) $(data : array<uint8>) {
            verify(length(data) == sz, "the whole file loaded into the buffer")
            // reference the buffer (no copy); it outlives the player below
            var p = video_open(unsafe(addr(data[0])), length(data))
            verify(p != null, "video_open from memory succeeds")
            while (video_decode(p)) {
                p |> get_data() $(rgb : array<uint8>#) {
                    verify(length(rgb) == video_width(p) * video_height(p) * 4, "borrowed RGBA is w*h*4")
                }
                frames++
            }
            video_close(p)
        }
    }
    return frames
}

[export]
def main() {
    let mpg = decode_from_memory("tests/fixtures/test.mpg")
    let ivf = decode_from_memory("tests/fixtures/test_av1.ivf")
    verify(mpg == 25, "MPEG-1 from memory decodes all 25 frames")
    verify(ivf == 25, "AV1 from memory decodes all 25 frames")
    print("dasVideo membuf: MPEG-1 {mpg} + AV1 {ivf} frames, both played from a borrowed buffer\n")
}
