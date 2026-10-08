#!/bin/bash

# Build the TensorFlow MLIR tools (tf-opt, tf-mlir-translate,
# flatbuffer_translate) at d7f515cc2fd8 (2024-07-23).
#
# Its third_party/llvm pin is acc159aea1e6, committed on the day
# llvm/llvm-project branched release/19.x (f2ccf80136a0, 2024-07-23), so the
# TOSA these tools emit should parse with the LLVM 19.1.x mlir-opt/soda-opt.
# TF 2.17.0 pins a 2024-05-31 LLVM and 2.18.0 a 2024-09-23 one, so neither
# release is as close as this commit.
#
# TensorFlow builds with Bazel and its own LLVM; no system LLVM is used. The
# Bazel version is the one this commit's .bazelversion asks for (6.5.0), and it
# is downloaded into WORK_DIR rather than installed system-wide.
#
# Usage:
#   ./scripts/external/setup-tensorflow-mlir.sh [WORK_DIR]
#
# WORK_DIR defaults to ../tensorflow, next to this repo's other tool builds
# (torch-mlir, llvm, soda-opt). Layout created inside it:
#   tensorflow/   source checkout
#   bin/          the pinned bazel, plus the built tools (copied from bazel-bin)
#   cache/        bazel output base and disk cache
#
# Overridable environment variables:
#   TF_COMMIT   full 40-char SHA to build (default below)
#   JOBS        parallel build jobs (default: number of CPUs)
#   PYTHON      interpreter handed to ./configure (default: python3)
#   BAZEL_ARGS  extra arguments for `bazel build`

set -e -o pipefail

TF_COMMIT="${TF_COMMIT:-d7f515cc2fd81799219ed68ea8cd5f19f84106a2}"
PROJ_URL="${PROJ_URL:-https://github.com/tensorflow/tensorflow.git}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BASE_DIR=$SCRIPT_DIR/../..

WORK_DIR="${1:-$BASE_DIR/../tensorflow}"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

SRC_DIR="${SRC_DIR:-$WORK_DIR/tensorflow}"
BIN_DIR="$WORK_DIR/bin"
CACHE_DIR="$WORK_DIR/cache"
PYTHON="${PYTHON:-python3}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"
BAZEL_VERSION=6.5.0

TARGETS=(
    //tensorflow/compiler/mlir:tf-opt
    //tensorflow/compiler/mlir:tf-mlir-translate
    //tensorflow/compiler/mlir/lite:flatbuffer_translate
)

for tool in git curl "$PYTHON"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: $tool could not be found. Exiting."
        exit 1
    fi
done
mkdir -p "$BIN_DIR" "$CACHE_DIR"


# Fetch only the pinned commit.
if [ ! -d "$SRC_DIR/.git" ]; then
    git init "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$PROJ_URL"
fi

if [ "$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null)" != "$TF_COMMIT" ]; then
    git -C "$SRC_DIR" fetch --depth 1 origin "$TF_COMMIT"
    git -C "$SRC_DIR" checkout --detach FETCH_HEAD
fi

[ "$(head -n1 "$SRC_DIR/.bazelversion")" = "$BAZEL_VERSION" ] || {
    echo "ERROR: $TF_COMMIT wants bazel $(head -n1 "$SRC_DIR/.bazelversion"), not $BAZEL_VERSION" >&2
    exit 1
}


# The pinned bazel, checked against its published checksum.
BAZEL="$BIN_DIR/bazel-$BAZEL_VERSION"
if [ ! -x "$BAZEL" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64)  BAZEL_PLATFORM=darwin-arm64 ;;
        Darwin-x86_64) BAZEL_PLATFORM=darwin-x86_64 ;;
        Linux-x86_64)  BAZEL_PLATFORM=linux-x86_64 ;;
        Linux-aarch64) BAZEL_PLATFORM=linux-arm64 ;;
        *) echo "ERROR: no bazel $BAZEL_VERSION binary for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
    esac
    URL=https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-$BAZEL_PLATFORM
    curl -fL "$URL" -o "$BAZEL.tmp"
    echo "$(curl -fL "$URL.sha256" | cut -d' ' -f1)  $BAZEL.tmp" | shasum -a 256 -c -
    chmod +x "$BAZEL.tmp"
    mv "$BAZEL.tmp" "$BAZEL"
fi


# ./configure looks for plain `bazel` on PATH.
ln -sf "$(basename "$BAZEL")" "$BIN_DIR/bazel"
export PATH="$BIN_DIR:$PATH"

# This commit only has Python lock files for 3.9-3.12; without a pin Bazel
# follows the newest python3 on PATH.
export HERMETIC_PYTHON_VERSION="${HERMETIC_PYTHON_VERSION:-3.12}"

# macOS with only the Command Line Tools: bazel's Apple toolchain insists on a
# full Xcode. BAZEL_USE_CPP_ONLY_TOOLCHAIN alone does not stop it being picked,
# so the plain cc toolchains are also given priority (see BAZEL_FLAGS below).
BAZEL_FLAGS=()
if [ "$(uname -s)" = Darwin ]; then
    # Recent macOS SDKs make libc++ reject TF's std::is_signed specializations.
    BAZEL_FLAGS+=(--copt=-Wno-invalid-specialization
                  --host_copt=-Wno-invalid-specialization)
fi
if [ "$(uname -s)" = Darwin ] && ! xcodebuild -version &> /dev/null; then
    export BAZEL_USE_CPP_ONLY_TOOLCHAIN=1
    BAZEL_FLAGS+=(--repo_env=BAZEL_USE_CPP_ONLY_TOOLCHAIN=1
                  --extra_toolchains=@local_config_cc_toolchains//:all)
fi

# ./configure with every optional backend off. It writes .tf_configure.bazelrc.
cd "$SRC_DIR"
PYTHON_BIN_PATH="$(command -v "$PYTHON")" \
TF_NEED_ROCM=0 TF_NEED_CUDA=0 TF_NEED_CLANG=0 TF_SET_ANDROID_WORKSPACE=0 \
TF_CONFIGURE_IOS=0 TF_ENABLE_XLA=0 CC_OPT_FLAGS="-Wno-sign-compare" \
USE_DEFAULT_PYTHON_LIB_PATH=1 \
    ./configure

"$BAZEL" --output_user_root="$CACHE_DIR/output" shutdown
"$BAZEL" --output_user_root="$CACHE_DIR/output" build \
    -c opt \
    --jobs="$JOBS" \
    --disk_cache="$CACHE_DIR/disk" \
    --verbose_failures \
    "${BAZEL_FLAGS[@]}" \
    $BAZEL_ARGS \
    "${TARGETS[@]}"

BAZEL_BIN="$("$BAZEL" --output_user_root="$CACHE_DIR/output" info -c opt "${BAZEL_FLAGS[@]}" bazel-bin)"
cp -f "$BAZEL_BIN/tensorflow/compiler/mlir/tf-opt" \
      "$BAZEL_BIN/tensorflow/compiler/mlir/tf-mlir-translate" \
      "$BAZEL_BIN/tensorflow/compiler/mlir/lite/flatbuffer_translate" \
      "$BIN_DIR/"

# The tools link libtensorflow_framework dynamically; their rpaths include
# @loader_path, so the library only has to sit next to them.
LIB="$(readlink "$BAZEL_BIN/tensorflow/libtensorflow_framework.2.dylib")"
cp -f "$BAZEL_BIN/tensorflow/$LIB" "$BIN_DIR/"
ln -sf "$LIB" "$BIN_DIR/libtensorflow_framework.2.dylib"

# Smoke test.
"$BIN_DIR/tf-opt" --version
"$BIN_DIR/tf-mlir-translate" --version
"$BIN_DIR/flatbuffer_translate" --version

cat <<EOF

TensorFlow $TF_COMMIT built; the tools are in $BIN_DIR

  tf-opt, tf-mlir-translate, flatbuffer_translate

To use them:

    export PATH="$BIN_DIR:\$PATH"

To rebuild after editing sources under $SRC_DIR, rerun this script.
EOF
