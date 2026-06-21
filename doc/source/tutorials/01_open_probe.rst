01 — Open and probe a video
===========================

The smallest useful dasVideo step: open an MPEG-1 file and read back **what it is**
— its size, frame rate, duration, and whether it carries an audio track. No
decoding yet, no window; just the opaque ``VideoPlayer?`` handle and the cheap info
getters. Everything later builds on this.

The library
-----------

``open_probe_tut.das`` is a tiny library: one function that opens a clip, copies
its info into a plain struct, and closes it again. ``video_open`` returns ``null``
on failure, so the caller checks ``ok`` before trusting the rest. The ``defer``
guarantees ``video_close`` runs however we leave the function — the canonical
open/close idiom you'll see in every tutorial.

.. literalinclude:: ../../../tutorials/01_open_probe/open_probe_tut.das
   :language: das
   :start-at: require video

Note the getters are all valid on a freshly-opened player — you don't have to
decode a frame first to learn the stream's shape. ``video_has_audio`` /
``video_samplerate`` describe the audio stream without enabling it (enabling audio
is a later step).

Self-verifying
--------------

Each tutorial ships a headless test that doubles as its runnable demo and its CI
gate. This one probes the bundled ``sample.mpg`` (an ffmpeg ``testsrc`` 64×48 clip
with a 44100 Hz tone) and checks the reported info against its known shape.

.. literalinclude:: ../../../tutorials/01_open_probe/test_open_probe.das
   :language: das
   :start-at: require open_probe_tut

Running it
----------

Run it from the **repo root** — the test opens its sample with a repo-root-relative
path, matching the convention the other tests use:

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . tutorials/01_open_probe/test_open_probe.das

prints::

   tutorial 01 ok: 64x48 @ 25 fps, 1.96 s, audio 44100 Hz

Next
----

:doc:`02_decode_rgba` starts decoding: the frame loop, the **borrow** model
(``get_data`` hands you the pixels without copying), and ``video_rewind`` to loop.
