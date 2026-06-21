04 — YUV on the GPU
===================

Tutorial 03 let the module convert each frame to RGBA on the CPU. This is the
faster route: borrow the decoder's **native YUV420p planes** (no conversion, no
copy), upload them to three ``GL_R8`` textures, and do the YUV→RGB in a fragment
shader. The CPU does nothing but hand over pointers, and ~2.7× less data crosses the
bus (1.5 bytes/pixel instead of 4).

.. video:: 04_yuv_shader.mp4

The borrow
----------

The YUV ``get_data`` overload hands you three planes — Y at full resolution, U (cb)
and V (cr) at quarter resolution. Each is packed at its own stride
(``video_y_stride`` / ``video_uv_stride``), which is macroblock-rounded and so may
exceed the display width; ``GL_UNPACK_ROW_LENGTH`` handles that on upload:

.. literalinclude:: ../../../examples/play_yuv_gl.das
   :language: das
   :start-at: player |> get_data() $(y, u, v
   :end-before: var dw, dh

The three samplers are bound to distinct texture units with ``@stage = 0/1/2`` (miss
this and every sampler reads unit 0 — the chroma samples the luma, and you get a
green/magenta image). The fragment shader applies the BT.601 studio-swing matrix,
matching pl_mpeg's own ``plm_frame_to_rgb`` so the output is identical to the RGBA
path, byte for byte.

Self-verifying
--------------

A headless test confirms the plane shapes the GPU path relies on — Y full-res, U/V
quarter-res — without a display:

.. literalinclude:: ../../../tutorials/04_yuv_shader/test_yuv_planes.das
   :language: das
   :start-at: require video

Run it
------

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . examples/play_yuv_gl.das -- \
       --video tutorials/04_yuv_shader/narration.mpg

Next
----

:doc:`05_audio_sync` adds the last piece: sound, and keeping the picture in step with it.
