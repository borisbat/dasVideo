options gen2

// dasVideo example — play a video as an animated texture on a spinning 3D cube,
// decoding straight from an in-memory buffer (the canonical use of the
// `video_open(data, size)` overload). The clip's bytes are read into a das array
// ONCE and the player references them for its whole life — no per-frame file IO,
// no re-decode-from-disk: load once, decode-to-texture every frame, reuse.
//
// The cube itself (shaders, geometry, transform, per-frame texture upload) lives in
// the tutorial's scene module, so this file is just the window + play-from-memory
// loop. Windowed (needs a display), so it is run locally / by hand, not in CI.
//
//   daslang -load_module <repo> examples/play_texture_cube_gl.das
//   ... --video clip.mpg     play your own MPEG-1 .mpg instead of Emma's intro
//   ... --max-frames N       auto-exit after N frames (smoke)
//   ... --shot out.png       write the first rendered frame to a PNG

require glfw/glfw_boost
require opengl/opengl_boost
require stbimage
require daslib/clargs
require daslib/defer
require daslib/fio
require video
require texture_cube_scene

[CommandLineArgs]
struct PlayArgs {
    @clarg_short = "f"
    @clarg_doc = "Video file to texture the cube with (MPEG-1 .mpg)"
    video : string = "assets/emma/emma_intro.mpg"

    @clarg_doc = "Auto-exit after N frames (0 = no limit)"
    max_frames : int

    @clarg_doc = "Play once and exit instead of looping"
    noloop : bool

    @clarg_doc = "Window pixel size (square)"
    size : int = 640

    @clarg_doc = "Write the first rendered frame to this PNG, then keep playing"
    shot : string

    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "Show this help and exit"
    help : bool
}

// Grab the current framebuffer to a PNG (flip vertically — GL origin is bottom-left).
def save_shot(fname : string; w, h : int) {
    var pixels : array<uint8>
    pixels |> resize(w * h * 4)
    glFinish()
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, unsafe(addr(pixels[0])))
    let row = w * 4
    var tmp : array<uint8>
    tmp |> resize(row)
    for (y in range(h / 2)) {
        let top = y * row
        let bot = (h - 1 - y) * row
        unsafe {
            memcpy(addr(tmp[0]), addr(pixels[top]), row)
            memcpy(addr(pixels[top]), addr(pixels[bot]), row)
            memcpy(addr(pixels[bot]), addr(tmp[0]), row)
        }
    }
    stbi_write_png(fname, w, h, 4, unsafe(addr(pixels[0])), w * 4)
    delete pixels
    delete tmp
}

[export]
def main : int {
    var r <- parse_args(type<PlayArgs>)
    if (r |> is_err) {
        print("error: {r |> unwrap_err}\n\n")
        print_help(get_command_info(type<PlayArgs>), "play_texture_cube_gl")
        return 1
    }
    let cfg <- r |> move_unwrap
    if (cfg.help) {
        print_help(get_command_info(type<PlayArgs>), "play_texture_cube_gl")
        return 0
    }

    let sz = int(stat(cfg.video).size)
    if (sz <= 0) {
        print("can't read video: {cfg.video}\n")
        return 1
    }

    // Read the whole clip into memory ONCE; the player references this buffer for
    // its entire life (the reference-semantics contract of the memory overload), so
    // everything below — open, decode, render — runs inside the load block.
    var rc = 0
    fopen(cfg.video, "rb") $(fh : file) {
        fload(fh, sz) $(data : array<uint8>) {
            rc = run_cube(cfg, data)
        }
    }
    return rc
}

def run_cube(cfg : PlayArgs; data : array<uint8>) : int {
    var player = video_open(unsafe(addr(data[0])), length(data))
    if (player == null) {
        print("no decodable video in: {cfg.video}\n")
        return 1
    }
    defer() { video_close(player) }
    let vw = video_width(player)
    let vh = video_height(player)
    if (vw <= 0 || vh <= 0) {
        print("no decodable video stream in: {cfg.video}\n")
        return 1
    }

    if (glfwInit() == 0) {
        print("can't init glfw\n")
        return 1
    }
    defer() { glfwTerminate() }
    glfwInitOpenGL(3, 3)
    var window = glfwCreateWindow(cfg.size, cfg.size, "dasVideo - texture cube", null, null)
    if (window == null) {
        print("can't create window\n")
        return 1
    }
    defer() { glfwDestroyWindow(window) }
    glfwMakeContextCurrent(window)
    glfwSwapInterval(1)
    create_cube_gl(vw, vh)

    var frame = 0
    let t0 = glfwGetTime()
    while (glfwWindowShouldClose(window) == 0) {
        glfwPollEvents()
        if (!video_decode(player)) {       // end of stream
            break if (cfg.noloop)
            video_rewind(player)
            continue
        }
        upload_current_frame(player, vw, vh)
        var dw, dh : int
        glfwGetFramebufferSize(window, dw, dh)
        glViewport(0, 0, dw, dh)
        let angle = 0.7f + float(glfwGetTime() - t0) * 0.6f   // open on a 3/4 view, then spin
        draw_cube(angle, dh > 0 ? float(dw) / float(dh) : 1.0)
        if (!empty(cfg.shot) && frame == 0) {
            save_shot(cfg.shot, dw, dh)
        }
        glfwSwapBuffers(window)
        frame++
        break if (cfg.max_frames > 0 && frame >= cfg.max_frames)
    }
    print("dasVideo texture cube: rendered {frame} frames\n")
    return 0
}
