03 — RGBA on the screen
=======================

Tutorials 01 and 02 stayed headless. Now we open a window and *show* the video:
borrow each decoded frame as RGBA, upload it to an OpenGL texture, and draw it on a
fullscreen quad. This is the "easy route" — the CPU converts to RGBA inside the
module and you hand the bytes straight to ``glTexSubImage2D``.

.. video:: 03_rgba_gl.mp4

The program
-----------

``examples/play_rgba_gl.das`` is the whole windowed player. The video-specific part
is tiny — open, then each frame ``get_data`` the RGBA bytes and upload them:

.. literalinclude:: ../../../examples/play_rgba_gl.das
   :language: das
   :start-at: Borrow the decoded RGBA
   :end-before: var dw, dh

Everything else is ordinary GLFW + OpenGL setup: one ``GL_RGBA8`` texture, a
fullscreen quad, and a vsync-paced loop that decodes a frame, uploads it, and draws.
It loops by default (``--noloop`` to play once) and takes a ``clargs`` CLI
(``--video`` / ``--scale`` / ``--max-frames`` / ``--shot``).

Run it
------

It needs a display, so run it by hand (not in CI):

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . examples/play_rgba_gl.das -- \
       --video tutorials/03_rgba_gl/narration.mpg

That plays the clip embedded above — Emma walking through this very tutorial — through
the RGBA path. Drop ``--video`` to play the built-in test pattern instead.

Next
----

:doc:`04_yuv_shader` does the same thing the *fast* way: skip the CPU conversion,
borrow the native YUV planes, and convert on the GPU.
