options gen2

// Tutorial 07 scene — a spinning 3D cube whose six faces are an animated video
// texture. The whole GL pipeline (shaders, geometry, transform, per-frame upload)
// lives here as plain functions so both the windowed example and the recording
// driver drive the same cube without duplicating any of it. The frames come from
// a VideoPlayer the caller opened (from a file, or — the point of this tutorial —
// from an in-memory buffer); this module only borrows the decoded RGBA and uploads
// it to one GL texture each frame.

module texture_cube_scene

require opengl/opengl_boost
require glsl/glsl_opengl
require daslib/safe_addr
require daslib/math_boost
require math
require video

// -- Shader: textured cube under a model/view/projection transform. The fragment
// stage just samples the video texture, so each face shows the live frame. --
var @in @location v_position : float3
var @in @location v_texcoord : float2
var @uniform v_model : float4x4
var @uniform v_view : float4x4
var @uniform v_projection : float4x4
var @inout f_texcoord : float2
var @uniform f_tex : sampler2D
var @out f_FragColor : float4

[vertex_program]
def vs_main {
    f_texcoord = v_texcoord
    gl_Position = v_projection * v_view * v_model * float4(v_position, 1.0)
}

[fragment_program]
def fs_main {
    f_FragColor = texture(f_tex, f_texcoord)
}

var program, vao, vbo, ebo, texture : uint

[vertex_buffer]
struct Vertex {
    pos : float3
    uv  : float2
}

// A unit cube centred on the origin. Each face carries the full video (uv 0..1,
// top-left origin so the picture lands upright), so the clip plays on all six.
let H = 0.5f
let vertices = [
    // +Z (front)
    Vertex(pos = float3(-H, H, H), uv = float2(0.0, 0.0)), Vertex(pos = float3(H, H, H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(H, -H, H), uv = float2(1.0, 1.0)), Vertex(pos = float3(-H, -H, H), uv = float2(0.0, 1.0)),
    // -Z (back)
    Vertex(pos = float3(H, H, -H), uv = float2(0.0, 0.0)), Vertex(pos = float3(-H, H, -H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(-H, -H, -H), uv = float2(1.0, 1.0)), Vertex(pos = float3(H, -H, -H), uv = float2(0.0, 1.0)),
    // +X (right)
    Vertex(pos = float3(H, H, H), uv = float2(0.0, 0.0)), Vertex(pos = float3(H, H, -H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(H, -H, -H), uv = float2(1.0, 1.0)), Vertex(pos = float3(H, -H, H), uv = float2(0.0, 1.0)),
    // -X (left)
    Vertex(pos = float3(-H, H, -H), uv = float2(0.0, 0.0)), Vertex(pos = float3(-H, H, H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(-H, -H, H), uv = float2(1.0, 1.0)), Vertex(pos = float3(-H, -H, -H), uv = float2(0.0, 1.0)),
    // +Y (top)
    Vertex(pos = float3(-H, H, -H), uv = float2(0.0, 0.0)), Vertex(pos = float3(H, H, -H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(H, H, H), uv = float2(1.0, 1.0)), Vertex(pos = float3(-H, H, H), uv = float2(0.0, 1.0)),
    // -Y (bottom)
    Vertex(pos = float3(-H, -H, H), uv = float2(0.0, 0.0)), Vertex(pos = float3(H, -H, H), uv = float2(1.0, 0.0)),
    Vertex(pos = float3(H, -H, -H), uv = float2(1.0, 1.0)), Vertex(pos = float3(-H, -H, -H), uv = float2(0.0, 1.0))]

// two triangles (b,b+1,b+2)(b+2,b+3,b) per face, b stepping by 4
let indices = fixed_array<int>(
    0, 1, 2, 2, 3, 0,          // +Z
    4, 5, 6, 6, 7, 4,          // -Z
    8, 9, 10, 10, 11, 8,       // +X
    12, 13, 14, 14, 15, 12,    // -X
    16, 17, 18, 18, 19, 16,    // +Y
    20, 21, 22, 22, 23, 20)    // -Y

// Model matrix: spin about Y plus a fixed tilt about X so the top and a side stay
// visible as it turns. Column-major (m[i] is column i), matching GLSL mat4.
def private cube_model(angle : float) : float4x4 {
    let cy = cos(angle)
    let sy = sin(angle)
    let tilt = 0.5f
    let cx = cos(tilt)
    let sx = sin(tilt)
    var m : float4x4
    m[0] = float4(cy, 0.0, -sy, 0.0)
    m[1] = float4(sy * sx, cx, cy * sx, 0.0)
    m[2] = float4(sy * cx, -sx, cy * cx, 0.0)
    m[3] = float4(0.0, 0.0, 0.0, 1.0)
    return m
}

//! Create the cube's GL objects and a `w`x`h` RGBA texture for the video frames.
//! Call once, after a GL context is current.
def public create_cube_gl(w, h : int) {
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
    glEnable(GL_DEPTH_TEST)
}

//! Borrow the player's current decoded frame (RGBA) and upload it into the cube
//! texture. `vw`x`vh` is the video size. Call after a successful video_decode.
def public upload_current_frame(player : VideoPlayer?; vw, vh : int) {
    player |> get_data() $(rgb : array<uint8>#) {
        glBindTexture(GL_TEXTURE_2D, texture)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw, vh, GL_RGBA, GL_UNSIGNED_BYTE, unsafe(addr(rgb[0])))
    }
}

//! Clear and draw the cube rotated to `angle` (radians) for a viewport of `aspect`.
def public draw_cube(angle, aspect : float) {
    glClearColor(0.05, 0.05, 0.08, 1.0)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    glUseProgram(program)
    v_model := cube_model(angle)
    v_view := look_at_rh(float3(0.0, 1.1, 3.0), float3(0.0, 0.0, 0.0), float3(0.0, 1.0, 0.0))
    v_projection := perspective_rh_opengl(PI * 0.25f, aspect, 0.1, 100.0)
    f_tex := texture
    vs_main_bind_uniform(program)
    fs_main_bind_uniform(program)
    glBindVertexArray(vao)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glDrawElements(GL_TRIANGLES, length(indices), GL_UNSIGNED_INT, null)
}
