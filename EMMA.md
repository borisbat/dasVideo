# Emma — the dasVideo presenter

**Emma** is the synthetic spokesperson for dasVideo / daslang: a fixed face + voice we
drive with any script to produce a talking-head clip (demo fixtures, tutorial intros,
release blurbs, "Emma says \<anything\>"). She is meant to be **reused a lot**, so this
file is the exact, reproducible recipe. Get a new line of Emma by following it verbatim.

> Pipeline in one line: **Kokoro TTS (her voice) → Sonic (talking-head, on a cloud GPU)
> → mp4**, then transcode as needed.

## The locked recipe (don't drift — this is the "good" config)

| Knob | Value | Why |
|---|---|---|
| **Face** | `assets/emma/emma_portrait_closed.jpg` | Head-and-shoulders, **mouth CLOSED**. The closed mouth is load-bearing — see gotchas. |
| **Voice** | Kokoro TTS, voice **`bf_emma`** (British female) | |
| **Pronunciation** | spell "das" as **"dahss"** | Kokoro says "dasVideo" as "dis video" otherwise. So `daslang`→`dahss lang`, `dasVideo`→`dahss video`. The longer "dahss" also reads more British, which suits Emma. |
| **Model** | **Sonic** (`github.com/jixiaozhong/Sonic`, SVD-based) | We tried SadTalker (uncanny) and Hallo (better, but motion still off even maxed). Sonic's temporal/video-diffusion motion is the one that landed. |
| **`--dynamic_scale`** | **0.5** | Sonic's lip/motion **floor**, not a "calmer is better" knob. **0.3 fades the lips out — the lipsync dies toward the end, even on a 6s clip; 0.5 sustains them full-length.** Too low and the talking read decays. |
| **`--seed`** | **42** | Deterministic. |
| **`inference_steps`** | **40** | demo.py default is 25; 40 sharpens per-frame detail (teeth). Edit the hardcoded value in `demo.py`. |
| **`min_resolution`** | **1024** | **1024 renders the mouth interior (teeth); 512 fills the open mouth with a dark void.** 1024 is the deliverable (~18 min/clip on a 32GB card with `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`). |

The canonical face is a **StyleGAN (thispersondoesnotexist) portrait — IRREPRODUCIBLE**
(every fetch is a different person). It's committed here precisely so we never lose her.
`emma_portrait_openmouth.jpg` is the earlier open-mouth variant, kept for reference; the
**closed-mouth one is the source we drive.**

## How to make a new Emma clip

1. **Generate her voice** (Kokoro server on `:8880`, OpenAI-compatible). Remember the
   "dahss" spelling for any `das*` word:
   ```
   POST http://127.0.0.1:8880/v1/audio/speech
   { "model":"kokoro", "voice":"bf_emma", "response_format":"wav",
     "input":"Hi, I'm Emma. ... entirely in dahss lang, using dahss video. ..." }
   ```
   Local Kokoro: `D:\kokoro\.venv\Scripts\python.exe -m uvicorn server:app --host 127.0.0.1 --port 8880` (cwd `D:\kokoro`).

2. **Upload** the wav + the closed-mouth portrait to the Sonic GPU box (see setup below).

3. **Run Sonic** (output to **local disk**, not the network volume — see gotchas):
   ```
   cd /workspace/Sonic
   PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True PYTHONPATH=/workspace/Sonic \
     /root/svenv/bin/python -u demo.py \
     <portrait>.jpg <line>.wav /root/out.mp4 \
     --dynamic_scale 0.3 --seed 42
   ```

4. **Download** `/root/out.mp4`. Verify by extracting frames (`ffmpeg ... tile`) and, for
   anything shipping, by *watching the motion* — stills hide the gremlins (lesson learned
   the hard way; every "looks fine in stills" still needs a motion check).

5. Transcode to whatever the target needs (MPEG-1 for the dasVideo fixture, etc.).

## Sonic GPU box setup (RunPod)

One-time, on a RunPod pod (RTX 4090 24GB works; 40–48GB for fast 1024 — see gotchas).
SSH config alias `runpod` drives it from the dev box.

- **Box:** Ubuntu, `/workspace` = persistent network volume (holds the repo + ~30GB
  weights), local `/` overlay = fast scratch + **outputs**.
- **Env** (`uv` venv on **local disk** `/root/svenv`, python 3.10):
  - `torch==2.2.2 torchvision==0.17.1 --index-url .../cu121`
  - Sonic `requirements.txt`, **plus** the deps it imports but doesn't pin:
    `opencv-python-headless==4.9.0.80` + `numpy==1.26.4` (4.9 is numpy-1.x-safe; newer
    opencv drags in numpy 2 and breaks torch), `accelerate==0.30.1`, `xformers==0.0.25.post1`.
- **Weights** → `/workspace/Sonic/checkpoints/`:
  `huggingface-cli download LeonJoe13/Sonic --local-dir checkpoints`,
  `... stabilityai/stable-video-diffusion-img2vid-xt --local-dir checkpoints/stable-video-diffusion-img2vid-xt`
  (the diffusers subdirs are what's used; the redundant single-file `svd_xt.safetensors`
  can be skipped), `... openai/whisper-tiny --local-dir checkpoints/whisper-tiny`.
- Run with `PYTHONPATH=/workspace/Sonic` (the `hallo`-style package isn't installed).

## Gotchas (each one cost real time — heed them)

- **Closed-mouth source is mandatory.** An open-smile/teeth source makes Sonic (and Hallo)
  anchor to "teeth showing" → mouth hangs open the whole time. A relaxed closed mouth gives
  natural open-on-vowel / close-on-consonant.
- **`dynamic_scale` is the lip/motion FLOOR — set it to 0.5, not lower.** Too low and the lips
  fade out partway (the lipsync dies toward the end, even on a 6s clip). 0.3 *looked* like a calm
  "sweet spot" but it under-drives the lips over time; 0.5 sustains the talking read full-length.
- **Frame the face BIG — it sets the lip pixel budget.** Sonic crops to the detected face and
  animates *inside* that crop, so a face sitting small/far back in frame gets too few pixels on
  the mouth and the lip motion washes out to near-static during speech. Measured: a `563²` face
  crop on a 1024 canvas went dead at 2–4s, while a `735²` crop on the same canvas articulated
  cleanly. Use a tight head-and-shoulders portrait where the face fills the frame.
- **Render at 1024 for teeth; the "decay" was `dynamic_scale`, not resolution.** A long detour
  taught this the hard way. At `min_resolution=512` the open mouth is a **dark void** (no teeth);
  1024 renders the interior. Separately, lips that go near-static mid/late-clip are NOT a
  resolution or length problem — that's `dynamic_scale=0.3` under-driving them; `0.5` sustains a
  full 18s clip end-to-end at 1024. So: **1024 + 0.5, any length.** **Diagnose on MOTION across the
  WHOLE clip (especially the middle and END)** — a 2–4s stills check happily passes a clip whose
  lips fade at second 9.
- **Write output to LOCAL disk (`/root`), never the network volume.** The RunPod network
  volume has a quota; when it fills, ffmpeg's output write fails as a cryptic
  `Broken pipe` at the encode step (the model finished fine). The real error only shows as
  `Disk quota exceeded` if you write a test mp4 to `/workspace` directly.
- **1024 on a 24GB card OOMs** (the FFN-GELU activation peak) — fix with **one line**:
  `unet.enable_forward_chunking()` right after `unet.to(weight_dtype)` in `sonic.py`. Zero
  quality loss (mathematically identical), but ~27s/step (~18 min for a master). A 40–48GB
  card runs 1024 unchunked at ~4× the speed — worth it if 1024 Emma becomes routine.
- **Kokoro mangles `das`** → use the `dahss` respelling (above).
- **imageio's bundled ffmpeg can also break** — point it at the system binary with
  `IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg` if needed (though the real culprit was usually the quota).
- **Background `nohup` runs can die on this box** (session teardown / empty logs). Use
  `setsid bash -c '... > log 2>&1' </dev/null &` for long detached renders, then poll the log.
- **Don't trust stills for sign-off.** Every quality call in this project was a motion call.
