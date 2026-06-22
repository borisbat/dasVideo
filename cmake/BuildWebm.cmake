# BuildWebm.cmake — WebM (AV1 video + Opus audio) support: fetch + compile nestegg
# (WebM/Matroska demux — a single C file) and libopus (Opus decode — native CMake),
# the same vendor-and-compile way as dav1d. Included only when DAS_VIDEO_DAV1D is ON,
# since WebM AV1 video decodes through dav1d. No meson / system deps; the consumer
# needs only cmake + a C compiler (which daspkg already requires).
include(FetchContent)

# ---- nestegg (WebM/Matroska demux) — pinned commit, single C file, zero deps ----
FetchContent_Declare(nestegg_src
    URL https://github.com/kinetiknz/nestegg/archive/1c9936b171b7e37efce87f7af247c7af0e3ea5b8.tar.gz
    SOURCE_DIR ${DAS_VIDEO_DIR}/vendor/nestegg)
FetchContent_MakeAvailable(nestegg_src)
set(NESTEGG ${DAS_VIDEO_DIR}/vendor/nestegg)

add_library(nestegg_dec STATIC ${NESTEGG}/src/nestegg.c)
target_include_directories(nestegg_dec PUBLIC ${NESTEGG}/include)
set_target_properties(nestegg_dec PROPERTIES C_STANDARD 99 POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_definitions(nestegg_dec PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(nestegg_dec PRIVATE /wd4244 /wd4267)
endif()

# ---- libopus (Opus decode) — pinned release, native CMake (no meson) ----
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
# opus's CMake never sets -fPIC, so its static lib defaults to non-PIC; linking it
# into our shared_module then fails on Linux (ld "recompile with -fPIC"). Force PIC
# for every target opus creates (read at target-creation time, so set before
# MakeAvailable). MSVC / macOS don't enforce this, so only the Linux lane caught it.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
FetchContent_Declare(opus_src
    URL https://github.com/xiph/opus/archive/refs/tags/v1.5.2.tar.gz
    SOURCE_DIR ${DAS_VIDEO_DIR}/vendor/opus)
FetchContent_MakeAvailable(opus_src)
# belt-and-suspenders in case opus overrode the default on its target
set_target_properties(opus PROPERTIES POSITION_INDEPENDENT_CODE ON)
# the static `opus` target is now available to link.
