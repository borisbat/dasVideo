Reference
=========

The ``video`` module. Every function takes the opaque ``VideoPlayer?`` handle returned
by :ref:`video_open <ref-lifecycle>` (except ``video_backend_ready``). Null handles are
tolerated — getters return zero, actions are no-ops.

.. _ref-lifecycle:

Lifecycle
---------

.. code-block:: das

    video_open(filename : string) : VideoPlayer?

Open a video file — an MPEG-1 ``.mpg``, or an AV1 ``.ivf`` when the module is built
with dav1d (the default; ``DAS_VIDEO_DAV1D``). The container format is auto-detected.
Returns a player handle, or ``null`` if the file can't be opened or has no decodable
stream. Audio is **disabled** until you call ``video_enable_audio`` — the video-only
paths carry no audio cost.

.. code-block:: das

    video_open(data : uint8 const?; size : int) : VideoPlayer?

Open from a **borrowed in-memory buffer** instead of a file, with the same format
auto-detection. The bytes are **referenced, not copied** — they must stay alive and
unchanged until ``video_close`` (the player reads from them throughout playback). This
is the path for embedded or preloaded clips you render-to-texture and replay, or to
open several players over one buffer. From a ``das`` array, pass the address
explicitly: ``video_open(unsafe(addr(buf[0])), length(buf))`` — the ``unsafe`` marks
the buffer-lifetime contract you're accepting.

.. code-block:: das

    video_close(player : VideoPlayer?)

Destroy the player and its decoder. Pair every ``video_open`` with a ``video_close``
(``defer() { video_close(player) }`` is the idiom).

Decoding
--------

.. code-block:: das

    video_decode(player : VideoPlayer?) : bool

Decode the next video frame. Returns ``true`` if a frame was produced, ``false`` at end
of stream. The frame is held by the player until the next ``video_decode`` — borrow it
with ``get_data`` before calling again.

.. code-block:: das

    video_rewind(player : VideoPlayer?)

Seek back to the start (both video and audio). Clears the held frame/audio batch. Use it
to loop.

Stream info
-----------

All cheap getters on the open stream:

.. code-block:: das

    video_width(player : VideoPlayer?)      : int      // display width, pixels
    video_height(player : VideoPlayer?)     : int      // display height, pixels
    video_framerate(player : VideoPlayer?)  : double   // frames per second
    video_samplerate(player : VideoPlayer?) : int      // audio sample rate (Hz)
    video_duration(player : VideoPlayer?)   : double   // stream length, seconds
    video_frame_time(player : VideoPlayer?) : double   // pts of the current frame, seconds
    video_has_ended(player : VideoPlayer?)  : bool     // true past end of stream

``video_y_stride`` / ``video_uv_stride`` give the **plane strides** for the YUV route —
the tightly-packed plane widths, which are macroblock-rounded and so may exceed the
display ``video_width``. The display size is always ``video_width`` × ``video_height``.

.. code-block:: das

    video_y_stride(player : VideoPlayer?)   : int      // Y plane stride (== plane width)
    video_uv_stride(player : VideoPlayer?)  : int      // U/V plane stride

Frame access (borrow)
---------------------

The current frame's pixels are borrowed inside a block as ``array<uint8>#`` views —
valid only inside the block and only until the next ``video_decode``. Two overloads of
``get_data``:

.. code-block:: das

    // packed RGBA8: width*height*4 bytes, top-left origin, always opaque (alpha 255)
    player |> get_data() $(rgb : array<uint8>#) { ... }

    // native YUV420p planes: Y full-res, U (cb) and V (cr) quarter-res, zero-copy.
    // Each plane is packed at its stride (video_y_stride / video_uv_stride).
    player |> get_data() $(y, u, v : array<uint8>#) { ... }

The RGBA route runs pl_mpeg's YUV→RGB on the CPU into a player-owned buffer. The YUV
route hands you the decoder's planes directly (no conversion, no copy) — convert on the
GPU for the cheaper path.

Audio (opt-in)
--------------

.. code-block:: das

    video_has_audio(player : VideoPlayer?)      : bool   // does the file carry an audio stream?
    video_enable_audio(player : VideoPlayer?)   : bool   // enable it; false if there is none
    video_audio_channels(player : VideoPlayer?) : int    // always 2 (pl_mpeg = interleaved stereo)

``video_enable_audio`` must be called (once, after open) before decoding audio. It only
enables a stream that exists, so the video-only paths never buffer audio packets.

.. code-block:: das

    video_decode_audio(player : VideoPlayer?) : bool     // decode the next batch; false at end
    video_audio_time(player : VideoPlayer?)   : double   // pts of the current batch, seconds
    video_audio_count(player : VideoPlayer?)  : int      // stereo frames in the batch (1152)

.. code-block:: das

    // interleaved stereo floats (count*2), normalized -1..1, borrowed for the block only
    player |> get_audio_data() $(s : array<float>#) { ... }

``append_to_pcm`` (dasAudio) takes ownership of the array it's given, so **clone** the
borrowed batch (``chunk := s``) before pushing it. See :doc:`usage` for the full
A/V-synced loop.

Backend probe
-------------

.. code-block:: das

    video_backend_ready() : int      // 1 once the native module has loaded + linked

A trivial smoke check used by the headless test to confirm the ``.shared_module`` is in.
