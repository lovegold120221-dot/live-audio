#!/usr/bin/env bash
# Download llama.cpp source for offline Android build.
# Run this once if FetchContent fails during Gradle build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$SCRIPT_DIR/android/src/main/cpp/llama_cpp"
LLAMA_VERSION="b4793"

if [ -f "$DEST_DIR/llama.h" ]; then
    echo "llama.cpp already present at $DEST_DIR"
    exit 0
fi

echo "Downloading llama.cpp $LLAMA_VERSION..."
mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

# Download key source files individually
BASE_URL="https://raw.githubusercontent.com/ggml-ai/llama.cpp/$LLAMA_VERSION"

for FILE in \
    ggml.h ggml.c \
    ggml-alloc.h ggml-alloc.c \
    ggml-backend.h ggml-backend.c \
    ggml-backend-reg.cpp \
    ggml-quants.h ggml-quants.c \
    llama.h llama.cpp \
    llama-grammar.h llama-grammar.cpp \
    unicode.h unicode.cpp \
    unicode_data.cpp \
    ggml-common.h \
    ggml-impl.h \
    ggml-cpu.h ggml-cpu.cpp \
    ggml-aarch64.h ggml-aarch64.cpp \
    ggml-metal.h ggml-metal.metal \
    llamafile.h llamafile.cpp \
    sgemm.h sgemm.cpp; do
    echo "  Downloading $FILE..."
    curl -sSfL "$BASE_URL/$FILE" -o "$FILE" || echo "  WARNING: Failed to download $FILE (may not exist)"
done

# Also download gguf-py directory if needed for reference
echo "Downloading include/ggml-metal.metal..."
mkdir -p include
curl -sSfL "$BASE_URL/include/ggml-metal.metal" -o "include/ggml-metal.metal" 2>/dev/null || true

echo ""
echo "llama.cpp source downloaded to: $DEST_DIR"
echo "You can now build the APK without network access for llama.cpp."