06 — One API, many containers (AV1 + WebM + Opus)
=================================================

Every tutorial so far played MPEG-1. This one plays **AV1** — the royalty-free codec
— with no change to your code. ``video_open`` sniffs the file's magic bytes and picks
the backend: pl_mpeg for an MPEG-1 ``.mpg``, dav1d for a raw AV1 ``.ivf``, and nestegg
+ dav1d + libopus for a **WebM** container carrying AV1 video alongside **Opus** audio.
Open, decode, borrow — the surface never names the codec.

.. video:: 06_webm.mp4

(That clip is Emma explaining WebM — and it plays as a WebM: the demo below decodes
the very thing she's describing, AV1 video and Opus sound, through the same calls.)

The library
-----------

``probe_media`` opens a path, decodes the whole stream, and reports what came out. It
is the MPEG-1 decode loop from tutorials 02 and 05 *verbatim* — ``video_decode`` for the
AV1 frames, ``video_enable_audio`` + ``video_decode_audio`` + the ``get_audio_data``
borrow for the Opus audio. The only thing that changed is the file you hand it.

.. literalinclude:: ../../../tutorials/06_webm/webm_tut.das
   :language: das
   :start-at: require video

Two notes. Opus always decodes at 48 kHz, so ``video_samplerate`` reports 48000 for any
WebM regardless of the source rate; ``video_audio_channels`` reports the real channel
count (1 or 2). And the AV1 path is **8-bit 4:2:0** only — 10-bit / HDR / 4:2:2 / 4:4:4
fail closed with a clear message rather than decoding wrong, by design.

Self-verifying
--------------

The test decodes the bundled ``sample.webm`` (Emma's WebM, 640×640 AV1 + stereo Opus)
and checks that both tracks came through — AV1 frames from dav1d, Opus batches from
libopus, at 48 kHz with real amplitude.

.. literalinclude:: ../../../tutorials/06_webm/test_webm_decode.das
   :language: das
   :start-at: require webm_tut

Running it
----------

Run it from the **repo root** — the test opens its sample with a repo-root-relative
path:

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . tutorials/06_webm/test_webm_decode.das

prints::

   tutorial 06 ok: 453 AV1 frames, 905 Opus batches at 48000Hz

The same ``examples/play_audio_gl.das`` from tutorial 05 plays this WebM on screen, with
sound, A/V-synced — point it at ``tutorials/06_webm/sample.webm`` and watch. Because the
API is format-agnostic, the windowed player needed no change to gain AV1 + WebM + Opus.

That closes the ladder. Anything not in the royalty-free set (H.264, VP9, Theora, …) you
decode yourself and feed the same borrow API — dasVideo ships the codecs whose patents
*and* licenses are both clear, and stays out of your way for the rest.
