# dasVideo — project instructions

Video playback for [daslang](https://dascript.org/): decode → frames + audio → your
renderer, with A/V sync. Public repo `github.com/borisbat/dasVideo` (MIT). A native
C++ module (`src/`) + a thin daslang surface (`daslib/`, from P1), modeled on
dasVulkan / dasImgui.

The global daslang **gen2** rules apply to every `.das` file. This file holds only
dasVideo-specific truths. Design rationale: `ORIGINAL_PLAN.md`. Phased work: `ROADMAP.md`.

## What's decided (don't relitigate — see ORIGINAL_PLAN.md)

- **Decode: pl_mpeg (MPEG-1) first → dav1d (AV1) later.** Royalty-free + permissive
  ONLY. No FFmpeg (bind it yourself), no Ogg/Theora (separate repo).
- **Output: player owns, consumer borrows.** RAII block accessors —
  `get_data() $(rgb : array<uint8>#) { ... }` (RGBA8 default) /
  `get_data() $(y, u, v : array<uint8>#) { ... }` (native YUV420p). Dims/strides/pts
  in a plain returnable struct. YUV→RGB is a C++ helper (interpreter speed; a
  placeholder until the CPU-shaders backend lands, then it moves back to daslang).
- **Audio + sync via dasAudio** — `play_sound_from_pcm_stream` / `append_to_pcm` /
  channel-status `consumed_position` (master clock) + `stream_que_length`
  (backpressure). Audio is the clock; video lookahead = 1 frame (double-buffer);
  underrun stalls the clock → auto-resync. Mirrors `strudel_player.das`.

## Build & run

The native module links a daslang SDK via `DASLANG_DIR` (FATAL_ERROR without it):

```
cmake -S . -B _build -DCMAKE_BUILD_TYPE=Release -DDASLANG_DIR=<daslang-root>
cmake --build _build --config Release
```

Output lands at `<repo>/dasModuleVideo.shared_module`. Editing C++ needs a rebuild;
the daslang surface (from P1) edits live. Run against it:

```
daslang -load_module <repo> tests/test_video.das
```

- **The daslang binary must be a DLL build** (`das_is_dll_build()` true) or the
  `.das_module` `initialize` never calls `register_dynamic_module` →
  `error[20605] missing prerequisite 'video'`. Dev box: the `daScript-video`
  worktree binary, or `d:/Work/daScript/bin/Release/daslang.exe`.
- **pl_mpeg is single-header** — `PL_MPEG_IMPLEMENTATION` is defined in exactly one
  TU (`src/dasVIDEO.cpp`).
- Non-MSVC optimized configs build `-fno-rtti` to match the daslang runtime ABI, or
  the `.shared_module` mislinks.

## daspkg

Registered in the daspkg index only once it actually decodes (ROADMAP P6). Consumers
pull via daspkg — `build()` → `cmake_build()` sets `DASLANG_DIR`. Local dev points
`DASLANG_DIR` at a checkout/worktree.

## Emma — the presenter

dasVideo's demo/tutorial clips are fronted by **Emma**, a fixed synthetic face + voice we
drive with any script (Kokoro TTS → Sonic talking-head → mp4). The locked, reproducible
recipe — face, voice, the "dahss" pronunciation fix, Sonic config, the GPU-box setup, and
the hard-won gotchas — is in **`EMMA.md`**. Read it before generating any Emma clip; the
canonical (irreproducible GAN) source faces live in `assets/emma/`.

## Workflow

The genesis scaffold went to master; further work via PRs. Lint is mandatory.
