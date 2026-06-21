cmake_minimum_required(VERSION 3.16)
project(dasVideo CXX C)

# DASLANG_DIR must point to the daslang SDK root (include/ + lib/). daspkg's
# cmake_build() sets this for consumers; local dev points it at a checkout/worktree.
if(NOT DEFINED DASLANG_DIR)
    message(FATAL_ERROR "DASLANG_DIR must be set to the daslang SDK root")
endif()

set(DAS_VIDEO_DIR ${CMAKE_CURRENT_LIST_DIR})

# pl_mpeg (single header) is compiled into the module TU via PL_MPEG_IMPLEMENTATION.
set(DAS_VIDEO_SRC
    ${DAS_VIDEO_DIR}/src/dasVIDEO.cpp
)

add_library(dasModuleVideo SHARED ${DAS_VIDEO_SRC})
target_compile_features(dasModuleVideo PRIVATE cxx_std_17)
target_compile_definitions(dasModuleVideo PRIVATE
    DAS_MOD_EXPORTS DAS_ENABLE_DLL=1
    $<$<CONFIG:Release>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:MinSizeRel>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:RelWithDebInfo>:DAS_NO_ASSERTIONS>
)
target_include_directories(dasModuleVideo PRIVATE
    ${DASLANG_DIR}/include
    ${DAS_VIDEO_DIR}/vendor
    ${DAS_VIDEO_DIR}/src
)
if(WIN32)
    if(EXISTS "${DASLANG_DIR}/lib/Release/libDaScriptDyn.lib")
        target_link_libraries(dasModuleVideo PRIVATE
            ${DASLANG_DIR}/lib/Release/libDaScriptDyn.lib
            ${DASLANG_DIR}/lib/Release/libDaScriptDyn_runtime.lib
        )
    else()
        target_link_libraries(dasModuleVideo PRIVATE
            ${DASLANG_DIR}/lib/libDaScriptDyn.lib
            ${DASLANG_DIR}/lib/libDaScriptDyn_runtime.lib
        )
    endif()
elseif(APPLE)
    target_link_libraries(dasModuleVideo PRIVATE
        ${DASLANG_DIR}/lib/liblibDaScriptDyn.dylib
        ${DASLANG_DIR}/lib/liblibDaScriptDyn_runtime.dylib
    )
else()
    target_link_libraries(dasModuleVideo PRIVATE
        ${DASLANG_DIR}/lib/liblibDaScriptDyn.so
        ${DASLANG_DIR}/lib/liblibDaScriptDyn_runtime.so
    )
endif()
if(MSVC)
    target_compile_options(dasModuleVideo PRIVATE /wd4005 /bigobj)
else()
    # daslang runtime libs are built -fno-rtti for optimized configs; match the ABI
    # or the .shared_module mislinks.
    target_compile_options(dasModuleVideo PRIVATE
        $<$<CONFIG:Release>:-fno-rtti>
        $<$<CONFIG:MinSizeRel>:-fno-rtti>
        $<$<CONFIG:RelWithDebInfo>:-fno-rtti>)
endif()
set_target_properties(dasModuleVideo PROPERTIES
    SUFFIX ".shared_module"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${DAS_VIDEO_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${DAS_VIDEO_DIR}"
)
