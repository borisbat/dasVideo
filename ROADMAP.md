# dasVideo — Roadmap

Living checklist. Frozen design rationale in [ORIGINAL_PLAN.md](ORIGINAL_PLAN.md).
No time/effort sizing — it takes what it takes.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

## P0 — Scaffold + CI (foundation; green from commit one)

- [x] CMake linking daslang via `DASLANG_DIR` (dasVulkan-style); `.shared_module` output
- [x] `.das_module` (loads `dasModuleVideo.shared_module`; needs `require daslib/fio`)
- [x] `vendor/pl_mpeg.h` (MIT, compiled into the module TU)
- [x] `LICENSE` (MIT), `README.md`, `.gitignore`, `.gitattributes`
- [x] `CLAUDE.md` (repo instructions for AI collaboration)
- [x] `doc/` Sphinx skeleton
- [x] empty module compiles + headless smoke passes (proven locally on Windows)
- [~] CI: Linux + macOS build + headless smoke (regular GitHub runners). **Windows CI
      is a fast-follow** — the module build is proven locally; the daslang Windows
      build still needs bison/flex + MSVC env wiring on `windows-latest`.

## P1 — pl_mpeg video (headless)

- [x] `video_open` → `VideoPlayer` handle (opaque); info via getters
      (width/height/framerate/samplerate/duration/frame_time, y/uv strides). A plain
      frame-info struct is ergonomic sugar deferred to the daslib boost layer.
- [x] `video_decode` → native YUV420p planes (borrow-until-next-decode)
- [x] `get_data` block accessor — YUV planes (zero-copy `array<uint8>#` views)
- [x] C++ YUV→RGB converter (`plm_frame_to_rgba`); `get_data` — RGBA8
- [~] headless decode-N-frames + checksum test (green: local Windows + CI Linux/macOS;
      Windows CI shares P0's fast-follow)

## P2 — GL output

- [x] `examples/play_rgba_gl` — RGBA → one texture, fullscreen quad; clargs CLI,
      loop-by-default (`--noloop`/`--max-frames`/`--scale`/`--shot`). Visually verified
      (test pattern renders in a window). Surfaced + fixed an opaque-alpha bug in the
      RGBA converter along the way.
- [ ] `examples/play_yuv_gl` — 3×`GL_R8` textures + YUV→RGB fragment shader

### Follow-ups

- [ ] **daslang teardown crash** (not dasVideo): clargs early-exit (e.g. `--help`) +
      the full multi-module GL example stack → `g_envTotal=1 at exit (Initialize/Shutdown
      not balanced)`. Normal playback exits clean. Isolated — clargs / glfw / stbimage /
      dasVideo are each individually fine; only the combined stack trips it. A daslang
      module Init/Shutdown accounting bug to chase upstream.

## P3 — Audio + sync

- [ ] decode MP2 → interleaved float PCM
- [ ] `play_sound_from_pcm_stream` + `append_to_pcm` top-up loop
- [ ] `consumed_position` master clock; `stream_que_length` backpressure
- [ ] `update()` loop: top-up / promote-when-due / drop-or-hold; double-buffered video
- [ ] silent / no-audio wall-clock fallback
- [ ] test with an audio-bearing clip

## P4 — dasImgui

- [ ] `image()` embed in an imgui window — flagship demo

## P5 — dav1d backend

- [ ] vendor dav1d; WebM demux; Opus/Vorbis audio decode
- [ ] behind the same `VideoSource` API; backend selection by probe/extension

## P6 — Docs + tutorials

- [ ] Sphinx reference content (per-API)
- [ ] tutorial ladder: open-probe → rgba-to-gl → yuv-shader → audio-sync → imgui-embed → (av1)
- [ ] recordings (voiced, self-verifying) per the standard pipeline

## Cross-cutting

- [ ] CI stays green every phase; `//!` docstrings written *with* the code
- [ ] daspkg-index entry (publish once demoable)

## Deferred

- [ ] **WASM target** — BLOCKED: daslang WASM backend lacks OpenGL + dasAudio. Revisit after
      that gap is closed upstream.
