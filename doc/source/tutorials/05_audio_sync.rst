05 — Sound, in sync
===================

The last rung: add audio, and keep the picture in step with it. dasVideo streams the
decoded MP2 audio into dasAudio and then **paces the video to the audio**, because the
audio device is the one clock you can't speed up or slow down. The video follows it.

.. video:: 05_audio_sync.mp4

(That clip is Emma — her voice decoded and played by dasVideo, her lips paced to it.
If it's in sync, the model works.)

Audio is opt-in
---------------

After opening, call ``video_enable_audio`` (it returns ``false`` if there's no audio
stream — the video-only paths never pay for audio). Then create a PCM stream and feed
it the borrowed samples; ``append_to_pcm`` takes ownership, so clone the borrow first:

.. literalinclude:: ../../../examples/play_audio_gl.das
   :language: das
   :start-at: Keep the PCM channel fed
   :end-before: let media_time

The master clock is the stream's ``consumed_position`` — the count of PCM frames the
device has actually played. Divide by the sample rate and you have media-time; show
the video frame whose timestamp is due. A muted clip falls back to wall-clock.

The looping subtlety
--------------------

A dasAudio PCM stream **finishes on underrun** — if its queue ever empties, the
channel dies and further ``append_to_pcm`` does nothing. So to loop you must never let
it drain: when the audio stream ends, rewind and keep feeding from the top, and anchor
the video at the cumulative samples fed (``total_fed``) so picture and sound restart
together. That's the whole reason the loop is shaped the way it is.

Self-verifying
--------------

A headless test confirms the audio decode + borrow path (no audio device needed — the
real playback is what you watch above):

.. literalinclude:: ../../../tutorials/05_audio_sync/test_audio_decode.das
   :language: das
   :start-at: require video

Run it
------

.. code-block:: bash

   cd <dasVideo>
   daslang -load_module . examples/play_audio_gl.das

With no arguments it plays Emma introducing dasVideo, with sound, A/V synced — the
out-of-the-box demo. That's the end of the ladder: open → decode → borrow → screen →
GPU → sound.
