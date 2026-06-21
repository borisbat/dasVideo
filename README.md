# dasVideo

Video playback for [daslang](https://dascript.org/) — decode a video file to frames
+ audio and hand them to your renderer, with A/V sync. A native C++ backend with a
thin daslang surface, modeled on [dasVulkan](https://github.com/borisbat/dasVulkan)
/ dasImgui.

> **Status: playable.** MPEG-1 video + MP2 audio decode, OpenGL output (RGBA and
> YUV-shader routes), and A/V-synced playback with sound all work on Windows / Linux /
> macOS. Next: a dasImgui embed, then the dav1d (AV1) backend. See [ROADMAP.md](ROADMAP.md).

## Design

- **Decode: pl_mpeg (MPEG-1) → dav1d (AV1).** Royalty-free, permissively-licensed codecs only.
- **Output: the player owns, the consumer borrows** — per-frame pixels via RAII block
  accessors: `get_data() $(rgb : array<uint8>#) { ... }` (RGBA8) or
  `get_data() $(y, u, v : array<uint8>#) { ... }` (native YUV planes).
- **Audio + sync via dasAudio** — push PCM, drive video off the audio clock.

Full rationale: [ORIGINAL_PLAN.md](ORIGINAL_PLAN.md). Phased checklist: [ROADMAP.md](ROADMAP.md).

## Licensing — two gates, both kept green

dasVideo ships only codecs that are **both** royalty-free (no codec patent dues) **and**
permissively licensed:

| Codec | Patents | Code |
|---|---|---|
| MPEG-1 + MP2 | expired (~2012) | [pl_mpeg](https://github.com/phoboslab/pl_mpeg) — MIT |
| AV1 + Opus / Vorbis | royalty-free by design | dav1d BSD-2, libopus/libvorbis BSD (P5) |

Out of scope **by design**: **FFmpeg** (bind it yourself if you need it),
H.264 / H.265 / AAC (patent pools), Ogg / Theora (a separate repo on demand).

## Vendored dependencies

| What | Version | License |
|---|---|---|
| [pl_mpeg](https://github.com/phoboslab/pl_mpeg) | master | MIT |

## Build

The native module links a daslang SDK; point `DASLANG_DIR` at its root (`include/` + `lib/`):

```
cmake -S . -B _build -DCMAKE_BUILD_TYPE=Release -DDASLANG_DIR=<daslang-root>
cmake --build _build --config Release
```

Output: `<repo>/dasModuleVideo.shared_module`. Run a script against it:

```
daslang -load_module <repo> tests/test_video.das
```

The daslang binary must be a DLL build (`das_is_dll_build()` true) — the `.das_module`
only loads the native module under that flag. As a daspkg package, consumers just
`daspkg install github.com/borisbat/dasVideo` (registered once it decodes — ROADMAP P6).

## Examples

Windowed players (need a display; the audio one also needs an audio device — so they
run by hand, not in CI). They loop by default and take a `clargs` CLI (`--video`,
`--scale`, `--max-frames`, `--shot out.png`, `--noloop`, `--help`):

```
daslang -load_module <repo> examples/play_rgba_gl.das    # RGBA → one texture
daslang -load_module <repo> examples/play_yuv_gl.das     # native YUV planes → GPU YUV→RGB
daslang -load_module <repo> examples/play_audio_gl.das   # video + sound, A/V synced (--mute to pace by wall-clock)
```

## License

MIT — see [LICENSE](LICENSE).
