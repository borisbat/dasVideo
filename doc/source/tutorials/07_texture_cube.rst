07 — Video as a texture (play from memory)
==========================================

The whole ladder so far played a clip to the screen. This last step plays it onto
something — a spinning 3D cube, with the video as a live texture on every face. The
trick that makes it natural is the **play-from-memory** overload: read the clip's bytes
into an array once, hand them to ``video_open``, and decode-to-texture every frame. No
per-frame file IO, no re-reading from disk — load once, reuse forever.

.. video:: 07_texture_cube.mp4

Load once, reference forever
----------------------------

``video_open(data, size)`` takes a borrowed buffer instead of a filename. It
**references** the bytes — it does not copy them — so the buffer has to outlive the
player. The idiom is to do everything inside the block that owns the loaded bytes:

.. literalinclude:: ../../../examples/play_texture_cube_gl.das
   :language: das
   :start-at: Read the whole clip into memory
   :end-before: def run_cube

``fload`` hands the block a ``data : array<uint8>`` view of the whole file; we open the
player against ``addr(data[0])`` and run the entire render loop while that view is still
alive. The moment ``video_open`` returns, the player is reading straight from your
buffer — exactly what you want for an embedded or preloaded clip you render to a texture
and replay.

Decode straight into the texture
--------------------------------

Each frame is the same borrow you've used since tutorial 02 — only now the destination
is a GL texture instead of the screen. ``get_data`` hands you the RGBA pixels for the
length of the block; upload them and let go:

.. literalinclude:: ../../../examples/texture_cube_scene.das
   :language: das
   :start-at: Borrow the player's current
   :end-before: Clear and draw

The cube's six faces all sample that one texture, so the clip plays on each of them as
it turns. Because the player owns the decoded frame and the consumer only borrows it,
there is never a copy between the decoder and the GPU.

Self-verifying
--------------

The cube is windowed, so the headless gate proves the part that matters in CI: that
play-from-memory decodes **pixel-identically** to play-from-file. Same frame count,
same checksum — a true drop-in.

.. literalinclude:: ../../../tutorials/07_texture_cube/test_texture_cube.das
   :language: das
   :start-at: require video

Running it
----------

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . examples/play_texture_cube_gl.das

opens Emma's intro on a spinning cube, decoded from a single in-memory buffer. Point it
at your own clip with ``--video clip.mpg``.

That's the ladder, end to end: open → decode → borrow → screen → GPU → sound → and now a
texture on geometry. The clip never left the buffer you loaded it into.
