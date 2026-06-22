Tutorials
=========

A ladder that builds up the dasVideo API one step at a time. 01–02 are headless
libraries with self-verifying tests; 03–05 open a window and put the video (and
sound) on screen, wrapping the runnable ``examples/``; 06 returns to a headless
library to show the same API decoding AV1 + WebM + Opus. Every step is fronted by
**Emma** — each tutorial is voiced, and she walks through it as the code runs.

.. toctree::
   :maxdepth: 1

   01_open_probe
   02_decode_rgba
   03_rgba_gl
   04_yuv_shader
   05_audio_sync
   06_webm
