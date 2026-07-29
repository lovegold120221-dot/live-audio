cmake_minimum_required(VERSION 3.22)
project(llama_bridge LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Suppress warnings from external code
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w")

# ---------- llama.cpp ----------
# If llama.cpp source is already present in a "llama_cpp" subdirectory, use it.
# Otherwise download via FetchContent.
set(LLAMA_CPP_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama_cpp")

if(EXISTS "${LLAMA_CPP_SOURCE_DIR}/include/llama.h")
    message(STATUS "Using local llama.cpp source: ${LLAMA_CPP_SOURCE_DIR}")
    set(llama_cpp_SOURCE_DIR "${LLAMA_CPP_SOURCE_DIR}")
else()
    message(STATUS "Downloading llama.cpp source via FetchContent...")
    include(FetchContent)
    FetchContent_Declare(
        llama_cpp
        GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
        GIT_TAG b4793
        GIT_SHALLOW TRUE
        GIT_PROGRESS TRUE
    )
    FetchContent_MakeAvailable(llama_cpp)
endif()

# ---------- llama.cpp source files ----------
if(NOT TARGET llama)
    # llama.cpp core source files (b4793 restructured into many files)
    set(LLAMA_SOURCES
        # ggml core
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml.c"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-alloc.c"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-quants.c"
        # ggml CPU backend
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/ggml-cpu.c"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/ggml-cpu-quants.c"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/ggml-cpu.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/ggml-cpu-aarch64.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/ggml-cpu-traits.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/llamafile/sgemm.cpp"
        # ggml backends / utils
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-backend.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-backend-reg.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-opt.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-threading.cpp"
        "${llama_cpp_SOURCE_DIR}/ggml/src/gguf.cpp"
        # llama.cpp core
        "${llama_cpp_SOURCE_DIR}/src/llama.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-adapter.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-arch.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-batch.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-chat.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-context.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-cparams.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-grammar.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-hparams.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-impl.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-kv-cache.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-mmap.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-model.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-model-loader.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-quant.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-sampling.cpp"
        "${llama_cpp_SOURCE_DIR}/src/llama-vocab.cpp"
        "${llama_cpp_SOURCE_DIR}/src/unicode.cpp"
        "${llama_cpp_SOURCE_DIR}/src/unicode-data.cpp"
    )

    # Build as a static library
    add_library(llama STATIC ${LLAMA_SOURCES})

    target_include_directories(llama PUBLIC
        "${llama_cpp_SOURCE_DIR}/include"       # llama.h
        "${llama_cpp_SOURCE_DIR}/ggml/include"  # ggml.h, ggml-alloc.h, etc.
    )

    # Internal include paths needed by source files
    target_include_directories(llama PRIVATE
        "${llama_cpp_SOURCE_DIR}"
        "${llama_cpp_SOURCE_DIR}/ggml/src"              # ggml-threading.h, etc.
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu"     # ggml-cpu-impl.h, etc.
        "${llama_cpp_SOURCE_DIR}/ggml/src/ggml-cpu/llamafile"  # sgemm.h
    )

    # ARM64 optimizations
    target_compile_definitions(llama PRIVATE
        GGML_USE_LLAMAFILE
        GGML_SCHED_MAX_COPIES=4
    )

    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
        target_compile_options(llama PRIVATE
            -march=armv8.2-a+dotprod
        )
    endif()
endif()

# ---------- JNI bridge (shared library) ----------
# JNI headers (jni.h) are provided by the NDK sysroot — no find_package needed
add_library(llama_bridge SHARED llama_bridge.cpp)
target_include_directories(llama_bridge PRIVATE
    "${llama_cpp_SOURCE_DIR}/include"
    "${llama_cpp_SOURCE_DIR}/ggml/include"
)
target_link_libraries(llama_bridge PRIVATE llama log)

# Install the .so into the jniLibs directory
set_target_properties(llama_bridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}"
)