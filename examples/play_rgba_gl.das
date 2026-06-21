options gen2

// dasVideo example — play a video into a fullscreen GL quad via the RGBA route.
// The player owns the pixels; each frame we borrow an RGBA view inside get_data
// and upload it to one GL_RGBA8 texture. Windowed (needs a display), so it is
// run locally / by hand, not in headless CI.
//
//   daslang -load_module <repo> examples/play_rgba_gl.das -- --video clip.mpg
//   ... --max-frames N   auto-exit after N frames (headless smoke)
//   ... --shot out.png   write the first rendered frame to a PNG

require glfw/glfw_boost
require opengl/opengl_boost
require glsl/glsl_opengl
require stbimage
require daslib/clargs
require daslib/defer
require daslib/safe_addr
require video

[CommandLineArgs]
struct PlayArgs {
    @clarg_short = "f"
    @clarg_doc = "Video file to play (MPEG-1 .mpg)"
    video : string = "tests/fixtures/test.mpg"

    @clarg_doc = "Auto-exit after N frames (0 = no limit)"
    max_frames : int

    @clarg_doc = "Play once and exit instead of looping"
    noloop : bool

    @clarg_doc = "Window pixel scale (0 = auto-enlarge small videos)"
    scale : int

    @clarg_doc = "Write the first rendered frame to this PNG, then keep playing"
    shot : string

    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "Show this help and exit"
    help : bool
}

var @in @location v_position : float2
var @in @location v_texcoord : float2
var @inout f_texcoord : float2
var @uniform f_tex : sampler2D
var @out f_FragColor : float4

[vertex_program]
def vs_main {
    f_texcoord = v_texcoord
    gl_Position = float4(v_position, 0.0, 1.0)
}

[fragment_program]
def fs_main {
    f_FragColor = texture(f_tex, f_texcoord)
}

var program, vao, vbo, ebo, texture : uint

[vertex_buffer]
struct Vertex {
    xy : float2
    uv : float2
}

// Fullscreen quad. uv.y grows top→bottom so the video's top-left origin lands
// upright on screen (first uploaded row is texture row 0, sampled at uv.y=0).
let vertices = [Vertex(
    xy = float2(-1.0,  1.0), uv = float2(0.0, 0.0)), Vertex(
    xy = float2( 1.0,  1.0), uv = float2(1.0, 0.0)), Vertex(
    xy = float2( 1.0, -1.0), uv = float2(1.0, 1.0)), Vertex(
    xy = float2(-1.0, -1.0), uv = float2(0.0, 1.0))]
let indices = fixed_array<int>(0, 1, 2, 2, 3, 0)

def create_gl_objects(w, h : int) {
    program = create_shader_program(@@vs_main, @@fs_main)
    glGenVertexArrays(1, safe_addr(vao))
    glBindVertexArray(vao)
    glGenBuffers(1, safe_addr(vbo))
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices, GL_STATIC_DRAW)
    bind_vertex_buffer(null, type<Vertex>)
    glGenBuffers(1, safe_addr(ebo))
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices, GL_STATIC_DRAW)
    glGenTextures(1, safe_addr(texture))
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, int(GL_RGBA), w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
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
        print_help(get_command_info(type<PlayArgs>), "play_rgba_gl")
        return 1
    }
    let cfg <- r |> move_unwrap
    if (cfg.help) {
        print_help(get_command_info(type<PlayArgs>), "play_rgba_gl")
        return 0
    }

    var player = video_open(cfg.video)
    if (player == null) {
        print("can't open video: {cfg.video}\n")
        return 1
    }
    defer() { video_close(player) }
    let vw = video_width(player)
    let vh = video_height(player)

    if (glfwInit() == 0) {
        print("can't init glfw\n")
        return 1
    }
    defer() { glfwTerminate() }
    glfwInitOpenGL(3, 3)
    var s = cfg.scale
    if (s <= 0) {                 // auto: enlarge small videos toward ~512px wide
        s = 512 / vw
        if (s < 1) { s = 1 }
    }
    var window = glfwCreateWindow(vw * s, vh * s, "dasVideo - RGBA", null, null)
    if (window == null) {
        print("can't create window\n")
        return 1
    }
    defer() { glfwDestroyWindow(window) }
    glfwMakeContextCurrent(window)
    glfwSwapInterval(1)           // vsync — pace the loop, don't peg a core
    create_gl_objects(vw, vh)

    var frame = 0
    while (glfwWindowShouldClose(window) == 0) {
        glfwPollEvents()
        if (!video_decode(player)) {       // end of stream
            break if (cfg.noloop)
            video_rewind(player)
            continue
        }
        // Borrow the decoded RGBA pixels (valid only in the block) and upload.
        player |> get_data() $(rgb : array<uint8>#) {
            glBindTexture(GL_TEXTURE_2D, texture)
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw, vh, GL_RGBA, GL_UNSIGNED_BYTE, unsafe(addr(rgb[0])))
        }
        var dw, dh : int
        glfwGetFramebufferSize(window, dw, dh)
        glViewport(0, 0, dw, dh)
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GL_COLOR_BUFFER_BIT)
        glUseProgram(program)
        f_tex := texture
        vs_main_bind_uniform(program)
        fs_main_bind_uniform(program)
        glBindVertexArray(vao)
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null)
        if (!empty(cfg.shot) && frame == 0) {
            save_shot(cfg.shot, dw, dh)
        }
        glfwSwapBuffers(window)
        frame++
        break if (cfg.max_frames > 0 && frame >= cfg.max_frames)
    }
    print("dasVideo RGBA: rendered {frame} frames\n")
    return 0
}
