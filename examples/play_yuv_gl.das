options gen2

// dasVideo example — play a video via the ADVANCED route: the native YUV420p planes
// are uploaded zero-copy into 3 GL_R8 textures and converted to RGB on the GPU in the
// fragment shader (BT.601, matching pl_mpeg's matrix). No CPU YUV->RGB. Windowed
// (needs a display), so it is run locally / by hand, not in headless CI.
//
//   daslang -load_module <repo> examples/play_yuv_gl.das -- --video clip.mpg
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
var @uniform@stage = 0 f_texY : sampler2D
var @uniform@stage = 1 f_texU : sampler2D
var @uniform@stage = 2 f_texV : sampler2D
var @out f_FragColor : float4

[vertex_program]
def vs_main {
    f_texcoord = v_texcoord
    gl_Position = float4(v_position, 0.0, 1.0)
}

// BT.601 studio-swing YUV->RGB, same coefficients pl_mpeg uses for plm_frame_to_rgb,
// so this matches the CPU RGBA path byte-for-byte.
[fragment_program]
def fs_main {
    let yv = (texture(f_texY, f_texcoord).x - 0.0625) * 1.16438
    let uu = texture(f_texU, f_texcoord).x - 0.5
    let vv = texture(f_texV, f_texcoord).x - 0.5
    let r = yv + 1.59603 * vv
    let g = yv - 0.39176 * uu - 0.81297 * vv
    let b = yv + 2.01723 * uu
    f_FragColor = float4(r, g, b, 1.0)
}

var program, vao, vbo, ebo : uint
var texY, texU, texV : uint

[vertex_buffer]
struct Vertex {
    xy : float2
    uv : float2
}

let vertices = [Vertex(
    xy = float2(-1.0,  1.0), uv = float2(0.0, 0.0)), Vertex(
    xy = float2(1.0,  1.0), uv = float2(1.0, 0.0)), Vertex(
    xy = float2(1.0, -1.0), uv = float2(1.0, 1.0)), Vertex(
    xy = float2(-1.0, -1.0), uv = float2(0.0, 1.0))]
let indices = fixed_array<int>(0, 1, 2, 2, 3, 0)

def make_plane_texture(w, h : int) : uint {
    var tex : uint
    glGenTextures(1, safe_addr(tex))
    glBindTexture(GL_TEXTURE_2D, tex)
    glTexImage2D(GL_TEXTURE_2D, 0, int(GL_R8), w, h, 0, GL_RED, GL_UNSIGNED_BYTE, null)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    return tex
}

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
    texY = make_plane_texture(w, h)            // full-res luma
    texU = make_plane_texture(w / 2, h / 2)    // quarter-res chroma
    texV = make_plane_texture(w / 2, h / 2)
}

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
        print_help(get_command_info(type<PlayArgs>), "play_yuv_gl")
        return 1
    }
    let cfg <- r |> move_unwrap
    if (cfg.help) {
        print_help(get_command_info(type<PlayArgs>), "play_yuv_gl")
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
    var s = cfg.scale
    if (s <= 0) {
        s = 512 / vw
        if (s < 1) { s = 1 }
    }
    var window = glfwCreateWindow(vw * s, vh * s, "dasVideo - YUV", null, null)
    if (window == null) {
        print("can't create window\n")
        return 1
    }
    defer() { glfwDestroyWindow(window) }
    glfwMakeContextCurrent(window)
    glfwSwapInterval(1)
    create_gl_objects(vw, vh)

    var frame = 0
    while (glfwWindowShouldClose(window) == 0) {
        glfwPollEvents()
        if (!video_decode(player)) {
            break if (cfg.noloop)
            video_rewind(player)
            continue
        }
        let ys = video_y_stride(player)
        let us = video_uv_stride(player)
        // Borrow the native YUV planes (valid only in the block) and upload them
        // zero-copy into the 3 plane textures.
        player |> get_data() $(y, u, v : array<uint8>#) {
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, texY)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, ys)
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw, vh, GL_RED, GL_UNSIGNED_BYTE, unsafe(addr(y[0])))
            glActiveTexture(GL_TEXTURE1)
            glBindTexture(GL_TEXTURE_2D, texU)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, us)
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw / 2, vh / 2, GL_RED, GL_UNSIGNED_BYTE, unsafe(addr(u[0])))
            glActiveTexture(GL_TEXTURE2)
            glBindTexture(GL_TEXTURE_2D, texV)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, us)
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw / 2, vh / 2, GL_RED, GL_UNSIGNED_BYTE, unsafe(addr(v[0])))
            glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
        }
        var dw, dh : int
        glfwGetFramebufferSize(window, dw, dh)
        glViewport(0, 0, dw, dh)
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GL_COLOR_BUFFER_BIT)
        glUseProgram(program)
        f_texY := texY
        f_texU := texU
        f_texV := texV
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
    print("dasVideo YUV: rendered {frame} frames\n")
    return 0
}
