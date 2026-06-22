options gen2

// Self-verifying gate for tutorial 07. The cube demo decodes the clip straight
// from an in-memory buffer (video_open(data, size)); this test proves that path
// produces *exactly* the same frames as opening the file by name — same count,
// identical pixels — so the reference-semantics overload is a true drop-in. The
// GL cube itself is windowed and verified by eye / the recording; this is the
// headless decode gate that runs in CI.

require video
require daslib/fio

struct Decoded {
    frames   : int
    checksum : uint
}

// Decode every frame of an opened player, folding RGBA pixels into a checksum.
def drain(player : VideoPlayer?) : Decoded {
    var d : Decoded
    while (video_decode(player)) {
        d.frames++
        player |> get_data() $(rgb : array<uint8>#) {
            for (b in rgb) {
                d.checksum += uint(b)
            }
        }
    }
    return d
}

def from_file(path : string) : Decoded {
    var p = video_open(path)
    verify(p != null, "open by filename")
    let d = drain(p)
    video_close(p)
    return d
}

def from_memory(path : string) : Decoded {
    var out : Decoded
    let sz = int(stat(path).size)
    verify(sz > 0, "clip exists")
    fopen(path, "rb") $(f : file) {
        fload(f, sz) $(data : array<uint8>) {
            // reference the borrowed bytes (no copy); the buffer outlives the player
            var p = video_open(unsafe(addr(data[0])), length(data))
            verify(p != null, "open from the in-memory buffer")
            out = drain(p)
            video_close(p)
        }
    }
    return out
}

[export]
def main() {
    let clip = "assets/emma/emma_intro.mpg"
    let file = from_file(clip)
    let mem = from_memory(clip)
    verify(file.frames > 0, "the clip decodes to at least one frame")
    verify(mem.frames == file.frames, "play-from-memory decodes the same frame count as play-from-file")
    verify(mem.checksum == file.checksum, "play-from-memory yields pixel-identical frames (reference semantics)")
    print("tutorial 07 ok: {mem.frames} frames from memory, pixel-identical to file (checksum {mem.checksum})\n")
}
