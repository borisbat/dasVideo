dasVideo
========

Video playback for `daslang <https://dascript.org/>`_: decode a video file to frames
plus audio and hand them to your renderer, with A/V sync. A native C++ module plus a
small daslang surface — **MPEG-1** (pl_mpeg), **AV1** (dav1d, as a raw ``.ivf`` or in a
**WebM** container alongside **Opus** audio via nestegg + libopus). Royalty-free,
permissively-licensed codecs only.

The design in one breath: **the player owns the decoded data, the consumer borrows it**
through RAII block accessors; **audio is the master clock** and video is paced to it.

.. code-block:: text

    daslang -load_module <repo> examples/play_audio_gl.das    # Emma introduces dasVideo

.. toctree::
   :maxdepth: 2

   usage
   tutorials/index
   reference
