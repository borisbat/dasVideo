options gen2

// Tutorial 02 — Decode frames and borrow their pixels.
//
// Building on tutorial 01: now we actually decode. `video_decode` advances one
// frame at a time and returns false at end of stream; the frame's packed RGBA8
// pixels are then *borrowed* inside a `get_data` block — a view that's valid only
// inside the block and only until the next decode, never copied. This is the
// "player owns, consumer borrows" model at the heart of dasVideo.
//
// This file is a library; the runnable is its test, `test_decode_rgba.das`.

require video
require daslib/defer

struct DecodeStats {
    frames   : int
    checksum : uint
    opaque   : bool    // every RGBA frame had an opaque first pixel (alpha 255)
}

// Decode every frame of `path`, borrowing each frame's RGBA8 pixels and folding
// them into a cheap checksum. The borrowed `rgb` is width*height*4 bytes, valid
// only inside the block — do your reading (or upload to a texture) there.
def public decode_stats(path : string) : DecodeStats {
    var player = video_open(path)
    if (player == null) return DecodeStats()
    defer() { video_close(player) }
    var st = DecodeStats(opaque = true)
    while (video_decode(player)) {
        st.frames++
        player |> get_data() $(rgb : array<uint8>#) {
            if (rgb[3] != 255u8) {
                st.opaque = false
            }
            for (b in rgb) {
                st.checksum += uint(b)
            }
        }
    }
    return st
}

// `video_rewind` seeks back to the start so you can loop. Decode to the end,
// rewind, decode again — the second pass yields the same frame count.
def public replay_count(path : string) : int {
    var player = video_open(path)
    if (player == null) return 0
    defer() { video_close(player) }
    while (video_decode(player)) {}
    video_rewind(player)
    var n = 0
    while (video_decode(player)) {
        n++
    }
    return n
}
