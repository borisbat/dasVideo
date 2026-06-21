// dasVideo native module — P0 scaffold.
//
// pl_mpeg (MPEG-1 video + MP2 audio, MIT) is vendored and compiled into this TU;
// the decode surface (VideoPlayer, get_data block accessors, audio) lands in P1.
// For now this proves the .shared_module builds and loads on every platform, and
// that pl_mpeg compiles into the module translation unit.
#include "daScript/daScript.h"

// pl_mpeg is a single-header library; the implementation belongs in exactly one TU.
#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"

namespace das {

// P0 probe: lets a headless test prove the module loaded and linked. The real
// decode API arrives in P1.
static int32_t video_backend_ready() {
    return 1;
}

class Module_dasVIDEO : public Module {
public:
    Module_dasVIDEO() : Module("video") {
        ModuleLibrary lib(this);
        lib.addBuiltInModule();
        addExtern<DAS_BIND_FUN(video_backend_ready)>(*this, lib, "video_backend_ready",
            SideEffects::none, "video_backend_ready");
        verifyAotReady();
    }
};

REGISTER_DYN_MODULE(Module_dasVIDEO, Module_dasVIDEO);

}

REGISTER_MODULE_IN_NAMESPACE(Module_dasVIDEO, das);
