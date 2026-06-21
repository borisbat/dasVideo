Usage
=====

Building the module
-------------------

dasVideo is a native module that links a daslang SDK. Point ``DASLANG_DIR`` at its root
(the directory holding ``include/`` and ``lib/``):

.. code-block:: bash

    cmake -S . -B _build -DCMAKE_BUILD_TYPE=Release -DDASLANG_DIR=<daslang-root>
    cmake --build _build --config Release

The build produces ``dasModuleVideo.shared_module`` at the repo root. The daslang binary
must be a **DLL build** (``das_is_dll_build()`` true) or the ``.das_module`` descriptor
never registers the native module. As a daspkg package, consumers just
``daspkg install github.com/borisbat/dasVideo``.

Load it into a script with ``-load_module`` and ``require video``:

.. code-block:: bash

    daslang -load_module <repo> myscript.das

.. code-block:: das

    require video

The borrow model — player owns, consumer borrows
------------------------------------------------

``video_open`` returns an opaque ``VideoPlayer?`` handle that owns the decoder and its
buffers. ``video_decode`` advances to the next frame; pixels are then **borrowed** for
the duration of a block — never copied unless you ask. Two routes:

.. code-block:: das

    var player = video_open("clip.mpg")
    defer() { video_close(player) }

    while (video_decode(player)) {
        // easy route: packed RGBA8, width*height*4 bytes, opaque
        player |> get_data() $(rgb : array<uint8>#) {
            upload_rgba(rgb, video_width(player), video_height(player))
        }
        // advanced route: the native YUV420p planes, zero-copy
        player |> get_data() $(y, u, v : array<uint8>#) {
            // Y is full-res; U,V are quarter-res. Each plane is tightly packed at its
            // plane width (the stride) — see video_y_stride / video_uv_stride.
        }
    }

The borrowed ``array<uint8>#`` views are valid **only inside the block** and only until
the next ``video_decode``. Upload them to a texture (or copy what you need) before the
block returns. ``examples/play_rgba_gl.das`` and ``examples/play_yuv_gl.das`` show both
routes against OpenGL; the YUV route uploads three ``GL_R8`` planes and converts to RGB
on the GPU (cheaper on CPU + bandwidth).

Audio and A/V sync
------------------

Audio is **opt-in** so the video-only paths stay zero-overhead. After opening, call
``video_enable_audio`` (it returns ``false`` if the file has no audio stream). Audio is
the **master clock**: you stream the decoded PCM into dasAudio and pace the video to how
much audio has actually been consumed.

.. code-block:: das

    require audio/audio_boost
    require daslib/jobque_boost

    let has_audio = video_enable_audio(player)
    let sid = play_sound_from_pcm_stream(video_samplerate(player), 2)
    var status_box = lock_box_create()
    status_box |> add_ref()
    set_status_update(sid, status_box)

The playback loop:

* **Top up** the PCM stream while it has slack — decode an audio batch with
  ``video_decode_audio``, borrow it with ``get_audio_data``, clone it (``append_to_pcm``
  takes ownership), and push. Throttle on the channel status's ``stream_que_length``.
* **Read the clock** — ``consumed_position`` (PCM frames the device has actually played)
  ÷ samplerate gives media-time. Show the video frame whose ``frame->time`` is due.
* **No audio / muted** — fall back to wall-clock pacing.

``examples/play_audio_gl.das`` is the full, A/V-synced player (and its default clip is
**Emma** introducing dasVideo). The sync model mirrors ``strudel_player.das`` in dasAudio.

Looping
-------

``video_rewind`` restarts the stream. For a clean A/V loop, let the audio queue drain,
then rewind and re-anchor the clock so picture and sound restart together (the audio
example does this — ``drain-then-restart``).
