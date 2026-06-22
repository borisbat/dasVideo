options gen2

// Recording driver for tutorial 07 (manual, local-only — NOT run in CI). Renders the
// spinning video-cube scene to an APNG one deterministic frame at a time, then muxes
// Emma's Kokoro voiceover + a daStrudel music bed into the committed mp4. Reuses the
// exact same scene module the windowed example drives, so the recording shows the
// real thing. Needs: a display, ffmpeg, daStrudel (shipped with daslang), and Kokoro
// TTS at :8880. See dasVulkan/skills/recording.md.
//
//   daslang -load_module <dasVideo> tutorials/07_texture_cube/recording/record_texture_cube.das

require ../../recording/tutorial_record_voiced.das
require ../../../examples/texture_cube_scene.das
require glfw/glfw_boost
require opengl/opengl_boost
require daslib/fio
require daslib/module_path
require daslib/safe_addr
require daslib/defer
require video

let REC = 640                  // square recording resolution

// glReadPixels returns bottom-up rows; capture_apng wants top-down (it re-flips to
// match the APNG writer). Flip the readback once here.
def flip_to_top_down(var px : array<uint8>; w, h : int) {
    let row = w * 4
    var tmp : array<uint8>
    tmp |> resize(row)
    for (y in range(h / 2)) {
        let top = y * row
        let bot = (h - 1 - y) * row
        unsafe {
            memcpy(addr(tmp[0]), addr(px[top]), row)
            memcpy(addr(px[top]), addr(px[bot]), row)
            memcpy(addr(px[bot]), addr(tmp[0]), row)
        }
    }
    delete tmp
}

[export]
def main {
    let here = get_this_module_dir()
    let repo = dir_name(dir_name(dir_name(here)))          // .../recording -> repo root
    let apng = path_join(here, "texture_cube.apng")
    let out_mp4 = path_join(dir_name(here), "07_texture_cube.mp4")
    let das_root = get_das_root()
    let daslang_exe = find_daslang_exe(das_root)
    let music = path_join(das_root, "examples/daStrudel/features/sf2_integration_full_ambient.das")
    let clip = path_join(repo, "assets/emma/emma_intro.mpg")

    let fps = 30
    let n_frames = 720                                     // 24s
    let frame_ms = 1000 / fps
    let dur_s = float(n_frames) / float(fps)

    // Narration. Caption is for the eye; voice is spelled for Kokoro bf_emma. ASCII
    // only. Frame anchors are spaced past each measured voice duration (+0.5s) so the
    // lines never talk over each other.
    say(0, "dasVideo tutorial 7 -- video as a texture",
        "das Video tutorial seven. Video, as a texture.")          // 4.1s
    say(137, "Read the whole clip into memory once",
        "Read the whole clip into memory. Once.")                  // 3.2s
    say(249, "video_open references the bytes -- no copy",
        "video open just references those bytes. No copy. No reading from disk again.")  // 5.8s
    say(438, "Decode each frame into one GL texture",
        "Every frame decodes straight into one G L texture.")      // 3.9s
    say(570, "An animated texture on a spinning cube",
        "And there it is. An animated texture. On a spinning cube.")  // 4.1s

    // Open the clip FROM MEMORY (the whole point) and keep the buffer alive for the
    // entire render below — everything runs inside the load block.
    let sz = int(stat(clip).size)
    if (sz <= 0) {
        panic("can't read clip: {clip}")
    }
    var ok = false
    fopen(clip, "rb") $(fh : file) {
        fload(fh, sz) $(data : array<uint8>) {
            ok = render_and_capture(data, apng, n_frames, frame_ms)
        }
    }
    if (!ok) {
        panic("capture failed")
    }
    if (!prepare_voiceover(apng)) {
        panic("voiceover failed -- is Kokoro running at :8880?")
    }
    if (!convert_to_mp4_voiced(apng, music, daslang_exe, out_mp4, dur_s, fps, -16, 100)) {
        panic("convert failed")
    }
    to_log(LOG_INFO, "[record] tutorial 07 done\n")
}

def render_and_capture(data : array<uint8>; apng : string; n_frames, frame_ms : int) : bool {
    var player = video_open(unsafe(addr(data[0])), length(data))
    if (player == null) {
        to_log(LOG_ERROR, "[record] video_open from memory failed\n")
        return false
    }
    defer() { video_close(player) }
    let vw = video_width(player)
    let vh = video_height(player)

    if (glfwInit() == 0) {
        to_log(LOG_ERROR, "[record] glfwInit failed\n")
        return false
    }
    defer() { glfwTerminate() }
    glfwInitOpenGL(3, 3)
    var window = glfwCreateWindow(REC, REC, "dasVideo - recording cube", null, null)
    if (window == null) {
        to_log(LOG_ERROR, "[record] window failed\n")
        return false
    }
    defer() { glfwDestroyWindow(window) }
    glfwMakeContextCurrent(window)
    create_cube_gl(vw, vh)

    return capture_apng(apng, REC, REC, n_frames, frame_ms) $(frame : int) {
        glfwPollEvents()
        if (!video_decode(player)) {              // loop the clip over the recording
            video_rewind(player)
            video_decode(player)
        }
        upload_current_frame(player, vw, vh)
        glViewport(0, 0, REC, REC)
        let angle = 0.7f + float(frame) * 0.015f   // deterministic spin (~1.3 turns over 18s)
        draw_cube(angle, 1.0)
        glFinish()
        var px : array<uint8>
        px |> resize(REC * REC * 4)
        unsafe {
            glReadPixels(0, 0, REC, REC, GL_RGBA, GL_UNSIGNED_BYTE, addr(px[0]))
        }
        flip_to_top_down(px, REC, REC)
        glfwSwapBuffers(window)
        return <- px
    }
}
