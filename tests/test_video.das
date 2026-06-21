options gen2

require video

// P0 headless smoke: proves the native module loaded + linked. No GPU / display /
// audio. Run: daslang -load_module <repo> tests/test_video.das
[export]
def main() {
    verify(video_backend_ready() == 1)
    print("dasVideo P0: backend ready\n")
}
