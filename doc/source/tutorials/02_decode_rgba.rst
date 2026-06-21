02 — Decode frames and borrow pixels
====================================

Tutorial 01 only read a clip's *shape*. Now we decode it. ``video_decode``
advances one frame at a time and returns ``false`` at end of stream; the frame's
pixels are then **borrowed** inside a ``get_data`` block — a view that's valid only
inside the block and only until the next decode, and is never copied. That borrow
is the heart of dasVideo's "player owns, consumer borrows" model.

.. video:: 02_decode_rgba.mp4

The library
-----------

``decode_stats`` runs the decode loop, borrows each frame's packed RGBA8 pixels,
and folds them into a checksum. The borrowed ``rgb`` is ``width*height*4`` bytes;
you do your reading (or your texture upload) **inside the block** and let go when it
returns. ``replay_count`` shows ``video_rewind``: decode to the end, rewind, decode
again, and you get the same frames back — that's how looping works.

.. literalinclude:: ../../../tutorials/02_decode_rgba/decode_rgba_tut.das
   :language: das
   :start-at: require video

Two things worth noting. The RGBA route (``get_data() $(rgb : array<uint8>#)``)
hands you pixels pl_mpeg has already converted to RGBA8 on the CPU — easy to upload
to one texture. There's also a zero-copy **YUV route**
(``get_data() $(y, u, v : array<uint8>#)``) that hands you the decoder's native
planes for GPU conversion; that's a later tutorial. And the borrow is read-only and
scoped: never stash the ``rgb`` reference to use after the block — by then the next
decode has reused the buffer.

Self-verifying
--------------

The test decodes the bundled ``sample.mpg`` (an ffmpeg ``testsrc`` 64×48 clip, 25
frames, no audio) and checks the frame count, that the pixels are non-zero and
opaque, and that ``video_rewind`` replays the whole stream.

.. literalinclude:: ../../../tutorials/02_decode_rgba/test_decode_rgba.das
   :language: das
   :start-at: require decode_rgba_tut

Running it
----------

Run it from the **repo root** — the test opens its sample with a repo-root-relative
path:

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . tutorials/02_decode_rgba/test_decode_rgba.das

prints::

   tutorial 02 ok: decoded 25 frames, checksum 0x2e0c99e

Next
----

:doc:`03_rgba_gl` puts those borrowed pixels on screen: upload the RGBA frame to an
OpenGL texture and draw it on a fullscreen quad in a window.
