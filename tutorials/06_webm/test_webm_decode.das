options gen2

// Self-verifying gate for tutorial 06. Opens the bundled WebM (AV1 video + Opus
// audio — Emma explaining WebM, in a WebM) and decodes it through the same API the
// MPEG-1 tutorials use, checking that both the AV1 video and the Opus audio came
// through. Headless — no display, no audio device.

require webm_tut

[export]
def main() {
    let m = probe_media("tutorials/06_webm/sample.webm")
    verify(m.width == 640 && m.height == 640, "the WebM reports its 640x640 size")
    verify(m.video_frames > 0, "AV1 video decodes through dav1d")
    verify(m.has_audio, "the WebM carries an Opus audio track")
    verify(m.samplerate == 48000, "Opus decodes at 48000 Hz")
    verify(m.audio_channels == 2, "the demo's Opus audio is stereo")
    verify(m.audio_batches > 0, "Opus audio decodes through libopus")
    verify(m.audio_peak > 0.01, "decoded audio is real (Emma's voice, not silence)")
    print("tutorial 06 ok: {m.video_frames} AV1 frames, {m.audio_batches} Opus batches at {m.samplerate}Hz\n")
}
