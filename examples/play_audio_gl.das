options gen2

// dasVideo example — play a video WITH SOUND, A/V synced. Audio is the master
// clock: decoded MP2 samples are streamed into dasAudio (play_sound_from_pcm_stream
// + append_to_pcm), and the video is paced to the stream's consumed_position. When
// the file has no audio (or --mute) the loop falls back to wall-clock pacing.
// Windowed + needs an audio device, so it is run locally / by hand, not in CI.
//
//   daslang -load_module <repo> examples/play_audio_gl.das    # Emma introduces dasVideo (default)
//   ... --video clip.mpg   play your own MPEG-1/MP2 file instead
//   ... --mute          ignore the audio track, pace by wall-clock
//   ... --max-frames N  auto-exit after N render iterations (local smoke)
//   ... --shot out.png  write the first displayed frame to a PNG

require glfw/glfw_boost
require opengl/opengl_boost
require glsl/glsl_opengl
require stbimage
require daslib/clargs
require daslib/defer
require daslib/safe_addr
require daslib/jobque_boost
require audio/audio_boost
require video
require math

// queued audio batches (each = PLM_AUDIO_SAMPLES_PER_FRAME / samplerate seconds)
// to keep ahead of the device; ~8 * 1152/44100 ≈ 200ms of slack.
let AUDIO_TARGET_CHUNKS = 8

[CommandLineArgs]
struct PlayArgs {
    @clarg_short = "f"
    @clarg_doc = "Video file to play (MPEG-1 .mpg with MP2 audio)"
    video : string = "assets/emma/emma_intro.mpg"

    @clarg_doc = "Ignore the audio track; pace video by wall-clock"
    mute : bool

    @clarg_doc = "Auto-exit after N render iterations (0 = no limit)"
    max_frames : int

    @clarg_doc = "Play once and exit instead of looping"
    noloop : bool

    @clarg_doc = "Window pixel scale (0 = auto-enlarge small videos)"
    scale : int

    @clarg_doc = "Write the first displayed frame to this PNG, then keep playing"
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

let vertices = [Vertex(
    xy = float2(-1.0,  1.0), uv = float2(0.0, 0.0)), Vertex(
    xy = float2(1.0,  1.0), uv = float2(1.0, 0.0)), Vertex(
    xy = float2(1.0, -1.0), uv = float2(1.0, 1.0)), Vertex(
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

def upload_frame(player : VideoPlayer?; vw, vh : int) {
    player |> get_data() $(rgb : array<uint8>#) {
        glBindTexture(GL_TEXTURE_2D, texture)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vw, vh, GL_RGBA, GL_UNSIGNED_BYTE, unsafe(addr(rgb[0])))
    }
}

def read_consumed(status_box : LockBox?) : uint64 {
    var consumed = 0ul
    status_box |> get() $(st : AudioChannelStatus#) {
        consumed = st.consumed_position
    }
    return consumed
}

def read_que(status_box : LockBox?) : int {
    var que = 0
    status_box |> get() $(st : AudioChannelStatus#) {
        que = st.stream_que_length
    }
    return que
}

def run_loop(player : VideoPlayer?; window : GLFWwindow?; cfg : PlayArgs; vw, vh : int; muted : bool; sid : uint64; status_box : LockBox?) {
    let rate = double(max(1, video_samplerate(player)))
    let fps = video_framerate(player)
    let frame_dur = fps > 0.0lf ? 1.0lf / fps : 1.0lf / 30.0lf
    // media-time origin: for the current playback loop, the frame with pts 0 plays
    // at this absolute clock value (audio consumed-seconds, or wall-clock when muted).
    var loop_offset = muted ? glfwGetTime() : 0.0lf
    var shown_pts = -frame_dur        // pts of the last decoded+shown frame (-dur => frame 0 is due now)
    var total_fed = 0ul               // cumulative audio sample-frames pushed (audio path)
    var ended = false                 // stream hit end and we are NOT looping
    var shot_saved = false
    var frame = 0
    var displayed = 0
    while (glfwWindowShouldClose(window) == 0) {
        glfwPollEvents()
        // Keep the PCM channel fed: a dasAudio PCM stream dies on underrun, so the
        // queue must never empty. When the audio stream ends we rewind and feed from the
        // top right away; the loop's audio plays after everything fed so far, so anchoring
        // the video at `total_fed` keeps picture and sound in sync across the boundary.
        if (!muted && !ended) {
            var que = read_que(status_box)
            while (que < AUDIO_TARGET_CHUNKS) {
                if (!video_decode_audio(player)) {
                    if (cfg.noloop) {
                        ended = true
                    } else {
                        video_rewind(player)
                        loop_offset = double(total_fed) / rate
                        shown_pts = -frame_dur
                    }
                    break
                }
                let count = video_audio_count(player)
                var chunk : array<float>
                // append_to_pcm takes ownership, so clone the borrowed batch first.
                player |> get_audio_data() $(s : array<float>#) {
                    chunk := s
                }
                append_to_pcm(sid, chunk)
                total_fed += uint64(count)
                que++
            }
        }
        let media_time = (muted ? (glfwGetTime() - loop_offset)
                                : (double(read_consumed(status_box)) / rate - loop_offset))
        // advance to the latest frame that is due; drop intermediates, upload only the last
        var decoded_any = false
        var hit_end = false
        while (media_time >= shown_pts + frame_dur) {
            if (video_decode(player)) {
                shown_pts = video_frame_time(player)
                decoded_any = true
            } else {
                hit_end = true
                break
            }
        }
        if (decoded_any) {
            upload_frame(player, vw, vh)
            displayed++
        }
        // Muted path loops off wall-clock (no audio channel to keep alive); the audio
        // path loops via the audio-end rewind above and just holds the last frame until then.
        if (hit_end && muted) {
            if (cfg.noloop) {
                ended = true
            } else {
                video_rewind(player)
                loop_offset = glfwGetTime()
                shown_pts = -frame_dur
            }
        }
        // noloop: exit once the stream ended and (audio path) its audio finished playing.
        break if (ended && (muted || double(read_consumed(status_box)) >= double(total_fed)))
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
        if (!empty(cfg.shot) && !shot_saved && displayed > 0) {
            save_shot(cfg.shot, dw, dh)
            shot_saved = true
        }
        glfwSwapBuffers(window)
        frame++
        break if (cfg.max_frames > 0 && frame >= cfg.max_frames)
    }
    if (muted) {
        print("dasVideo audio (muted/wall-clock): {frame} iters, {displayed} frames displayed\n")
    } else {
        let consumed = read_consumed(status_box)
        print("dasVideo audio: {frame} iters, {displayed} frames displayed, {consumed} audio frames consumed ({double(consumed) / rate} s)\n")
    }
}

[export]
def main : int {
    var r <- parse_args(type<PlayArgs>)
    if (r |> is_err) {
        print("error: {r |> unwrap_err}\n\n")
        print_help(get_command_info(type<PlayArgs>), "play_audio_gl")
        return 1
    }
    let cfg <- r |> move_unwrap
    if (cfg.help) {
        print_help(get_command_info(type<PlayArgs>), "play_audio_gl")
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
    let has_audio = !cfg.mute && video_enable_audio(player)
    let muted = !has_audio

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
    var window = glfwCreateWindow(vw * s, vh * s, "dasVideo - audio", null, null)
    if (window == null) {
        print("can't create window\n")
        return 1
    }
    defer() { glfwDestroyWindow(window) }
    glfwMakeContextCurrent(window)
    glfwSwapInterval(1)
    create_gl_objects(vw, vh)

    if (muted) {
        if (cfg.mute) {
            print("playing muted (wall-clock paced)\n")
        } else {
            print("no audio track — wall-clock paced\n")
        }
        run_loop(player, window, cfg, vw, vh, true, 0ul, null)
    } else {
        with_audio_system() {
            let sid = play_sound_from_pcm_stream(video_samplerate(player), 2)
            var status_box = lock_box_create()
            status_box |> add_ref()
            set_status_update(sid, status_box)
            run_loop(player, window, cfg, vw, vh, false, sid, status_box)
            // teardown: detach, drop our ref, wait for the audio thread, free
            unset_status_update(sid)
            clear_status(status_box)
            var box_ptr = status_box
            status_box |> release()
            box_ptr |> join()
            unsafe(lock_box_remove(box_ptr))
        }
    }
    return 0
}
