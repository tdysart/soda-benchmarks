#!/bin/bash

# Build llvm-cbe (LLVM IR -> C backend) against an existing LLVM install.
#
# Used by ll_to_c_cbe.sh, which feeds soda-opt's LLVM 19 IR to bambu v2023.1
# as C (see llvm_to_verilog_bambu2023.mk, in the same directory).
#
# llvm-cbe tracks one LLVM major version per commit. 21569b994b is the last
# commit targeting LLVM 19.1 (the next one, 379d105c2c, moves to LLVM 20), so
# it matches the LLVM soda-opt is built with.
#
# Usage:
#   LLVM_CONFIG=/path/to/llvm/install/bin/llvm-config ./scripts/reference/bambu2023/setup-llvm-cbe.sh [WORK_DIR]
#
# WORK_DIR defaults to builds/llvm-cbe in this repo. The binary ends up at
# WORK_DIR/build/tools/llvm-cbe/llvm-cbe.
#
# Overridable environment variables:
#   LLVM_CONFIG     llvm-config of the LLVM to build against (default: on PATH)
#   LLVM_CBE_COMMIT full 40-char SHA to build (default below)
#   JOBS            parallel build jobs (default: number of CPUs)

set -e -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BASE_DIR=$SCRIPT_DIR/../../..

LLVM_CBE_COMMIT="${LLVM_CBE_COMMIT:-21569b994b019c711c5631edf1e7273332138f3d}"
PROJ_URL="${PROJ_URL:-https://github.com/JuliaHubOSS/llvm-cbe.git}"
LLVM_CONFIG="${LLVM_CONFIG:-llvm-config}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

WORK_DIR="${1:-$BASE_DIR/builds/llvm-cbe}"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
BUILD_DIR="$WORK_DIR/build"

for tool in git cmake ninja "$LLVM_CONFIG"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: $tool could not be found. Exiting."
        exit 1
    fi
done

LLVM_VERSION="$("$LLVM_CONFIG" --version)"
if [ "${LLVM_VERSION%%.*}" != "19" ]; then
    echo "WARNING: $LLVM_CONFIG is LLVM $LLVM_VERSION; llvm-cbe $LLVM_CBE_COMMIT targets LLVM 19.1."
fi


# Fetch only the pinned commit.
if [ ! -d "$WORK_DIR/.git" ]; then
    git init "$WORK_DIR"
    git -C "$WORK_DIR" remote add origin "$PROJ_URL"
fi

if [ "$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)" != "$LLVM_CBE_COMMIT" ]; then
    git -C "$WORK_DIR" fetch --depth 1 origin "$LLVM_CBE_COMMIT"
    git -C "$WORK_DIR" checkout --detach FETCH_HEAD
fi


# llvm-cbe links the shared libLLVM when built against an installed LLVM. An
# LLVM built with static libraries only (the LLVM default) has no libLLVM, so
# link its component libraries instead.
if [ "$("$LLVM_CONFIG" --shared-mode)" = "static" ]; then
    PATCH="$SCRIPT_DIR/llvm-cbe-static-llvm-link.patch"
    if git -C "$WORK_DIR" apply --check "$PATCH" 2> /dev/null; then
        git -C "$WORK_DIR" apply "$PATCH"
    elif ! git -C "$WORK_DIR" apply --reverse --check "$PATCH" 2> /dev/null; then
        echo "ERROR: could not apply $PATCH to $WORK_DIR"
        exit 1
    fi
fi

# Match LLVM's RTTI setting, or linking fails on missing typeinfo symbols.
CXX_FLAGS=""
if [ "$("$LLVM_CONFIG" --has-rtti)" = "NO" ]; then
    CXX_FLAGS="-fno-rtti"
fi

cmake -S "$WORK_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="$CXX_FLAGS" \
    -DLLVM_DIR="$("$LLVM_CONFIG" --cmakedir)"

cmake --build "$BUILD_DIR" -j "$JOBS"

LLVM_CBE_BIN="$BUILD_DIR/tools/llvm-cbe/llvm-cbe"
"$LLVM_CBE_BIN" --version

cat <<EOF

llvm-cbe $LLVM_CBE_COMMIT built against LLVM $LLVM_VERSION:

    $LLVM_CBE_BIN

Pass it to the bambu2023 make targets as LLVM_CBE=$LLVM_CBE_BIN
EOF
