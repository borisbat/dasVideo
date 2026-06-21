dasVideo
========

Video playback for `daslang <https://dascript.org/>`_: decode a video file to frames
plus audio and hand them to your renderer, with A/V sync. A native C++ module (a thin
pl_mpeg wrapper) plus a small daslang surface — **pl_mpeg (MPEG-1) now, dav1d (AV1)
later**. Royalty-free, permissively-licensed codecs only.

The design in one breath: **the player owns the decoded data, the consumer borrows it**
through RAII block accessors; **audio is the master clock** and video is paced to it.

.. code-block:: text

    daslang -load_module <repo> examples/play_audio_gl.das    # Emma introduces dasVideo

.. toctree::
   :maxdepth: 2

   usage
   tutorials/index
   reference
