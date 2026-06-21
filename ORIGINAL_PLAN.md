# dasVideo — Original Plan (frozen design rationale)

dasVideo is the video-playback module for the [daslang](https://dascript.org/) language:
decode a video file to frames + audio and hand them to the consumer for display, with A/V
sync. A native C++ backend with a thin daslang surface, modeled on dasImgui / dasVulkan.

This document freezes the **why**. The living, phased checklist is in [ROADMAP.md](ROADMAP.md).

## Scope / non-goals

- **In:** royalty-free, permissively-licensed decode only. pl_mpeg (MPEG-1) first, dav1d (AV1) next.
- **Out, by design:**
  - **FFmpeg** — not bound here. daslang is an open-source project; if you need ffmpeg, bind ffmpeg.
  - **Ogg / Theora / VP8 / VP9 / …** — a separate repository on demand, not this one.
  - The point of both exclusions: every binary dasVideo ships in CI/releases stays clean on **both** licensing gates below.

## Licensing — two independent gates

A library can be permissively licensed and *still* drag codec patent royalties, because the
**code** and the **codec** are licensed separately. A public, MIT repo that ships binaries needs
**both** gates green:

1. **Software license** (copyright) — can you link it into MIT code and ship the binary? MIT/BSD/Apache: yes.
2. **Codec patents** (royalties) — even a BSD-licensed decoder can owe per-unit royalties for the *format* it decodes.

Royalty-free **and** permissively-licensed sweet spots — what dasVideo ships:

| Codec | Patent status | Code license |
|---|---|---|
| MPEG-1 video + MP2 audio | Expired (~2012) | pl_mpeg — MIT |
| AV1 + Opus / Vorbis | Royalty-free by design (AOMedia / Xiph) | dav1d BSD-2, libopus/libvorbis BSD |

Avoided: H.264 / H.265 / AAC (active patent pools); FFmpeg / libVLC (LGPL/GPL weight).

## Decode backends

- **pl_mpeg** (MIT, single header, zero external deps): demux + MPEG-1 video + MP2 audio, in the
  box, builds on every platform. The "stb_image of video" — it proves the *entire* rail at
  near-zero integration cost.
- **dav1d** (BSD-2): AV1 **video only**. Container demux (WebM) + Opus/Vorbis audio decode are
  separate libraries, assembled behind the same `VideoSource` API. A later phase.

Common denominators across backends, so the daslang surface doesn't care who decoded:
- video = **YUV 4:2:0 planar, 8-bit** planes + pts
- audio = **interleaved float32 PCM** + sample rate + pts

Tier-1 constraint: 8-bit 4:2:0 only; 10-bit/HDR or 4:2:2/4:4:4 fail-closed with a clean error
for now (fold in later).

## Output model — player owns, consumer borrows

The consumer never allocates or frees per frame. A `VideoPlayer` (a daslang handle wrapping the
decoder) owns all memory; per-frame pixels are exposed through **block accessors** with RAII temp
lifetime:

```
player |> get_data() $(rgb : array<uint8>#) { ... }        // packed RGBA8 (default, easy route)
player |> get_data() $(y, u, v : array<uint8>#) { ... }     // native YUV420p planes, zero-copy
```

- Lifetime is lexically the block — a view can't escape and can't go stale. (`array<uint8>#`
  can't be a struct field, so the block accessor *is* the clean way to hand out the bytes.)
- Dimensions / strides / pts live in a plain returnable struct (no `#`) — GL upload of
  stride-padded planes needs `GL_UNPACK_ROW_LENGTH`.
- **Default convert = RGBA8** (GL/imgui-aligned, 4-byte rows).
- **YUV→RGB convert is a C++ helper**, for interpreter speed — explicitly a placeholder. When
  "CPU shaders" (the vectorize-or-error backend) become first-class, the converter moves back to
  daslang and the C++ helper is deleted.

## Audio + A/V sync — via dasAudio, no new infrastructure

dasAudio's streaming PCM voice already provides every primitive, and its command stream already
handles the cross-context / thread-safe handoff — so dasVideo builds **no ring buffer and opens
no audio device**. Audio mixes through the app's existing dasAudio graph.

| Need | dasAudio call |
|---|---|
| create the streaming voice | `play_sound_from_pcm_stream(rate, channels, sid)` |
| push PCM | `append_to_pcm(sid, samples : array<float>)` (moves it) |
| master clock | status box → `consumed_position` ÷ rate (seconds) |
| backpressure | status box → `stream_que_length` (or `pushed_frames − consumed_position`) |

**Audio is the master clock.** Per tick, from the app's render loop:

1. top up audio until ~target buffered (backpressure stops the push),
2. `clock = consumed_position / rate`,
3. promote the decoded-ahead video frame when `pts ≤ clock`; **drop** if behind, **hold** if ahead.

- **Video lookahead = 1 frame (double-buffer); audio buffers deep.** That asymmetry is the trick.
- `consumed_position` excludes silence → on underrun the clock *stalls*, video holds, and they
  auto-resync when audio resumes. Starvation degrades gracefully instead of drifting.
- No audio / muted → swap the clock source to an accumulated wall-time `dt`; identical loop.

This mirrors strudel's existing main-thread player loop (`strudel_player.das`), scheduling video
frames against the same clock instead of musical events.

## Output targets

GL first (`dasGlfw` + `dasOpenGL`): one-texture RGBA and 3×`GL_R8` + YUV→RGB shader examples.
dasImgui `image()` embed next (the flagship demo). dasVulkan image possible later.

## Deferred: WASM

pl_mpeg itself builds for WASM, but the daslang **WASM backend currently lacks OpenGL + dasAudio
support** — a known gap to be closed upstream first. WASM is therefore a separate, later phase,
not a cross-cutting concern.
