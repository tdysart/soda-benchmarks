#!/bin/bash

# Build torch-mlir at 43506726853b (2024-08-08), the last commit before
# torch-mlir moved its LLVM submodule past the LLVM release/19.x branch point.
# Its externals/llvm-project is pinned to d16b21b17d13 (LLVM 19 dev,
# 2024-06-28), so this is the closest torch-mlir to LLVM 19.1.x.
#
# This is an in-tree build: it compiles the bundled LLVM/MLIR together with
# torch-mlir, so no system LLVM is used. Its MLIR output (TOSA, linalg) is
# consumed by LLVM 19.1.x mlir-opt/soda-opt.
#
# Verified on macOS arm64 (2026-09-24) with PYTHON=python3.12: builds in about
# 10 minutes on 14 cores, and exports the pytorch-to-verilog 3mm example.
#
# Usage:
#   PYTHON=python3.12 ./scripts/external/setup-torch-mlir.sh [WORK_DIR]
#
# WORK_DIR defaults to builds/torch-mlir in this repo. Layout created inside it:
#   torch-mlir/   source checkout (plus llvm-project and stablehlo submodules)
#   venv/         Python venv with torch 2.4.0 (CPU)
#   build/        CMake/Ninja build tree
#
# Overridable environment variables:
#   TORCH_MLIR_COMMIT  full 40-char SHA to build (default below)
#   PYTHON             interpreter used to create the venv; torch 2.4 has
#                      wheels for Python 3.8-3.12 (default: python3)
#   TORCH_SPEC         pip spec for torch (default: torch==2.4.0)
#   BUILD_TYPE         Release | RelWithDebInfo | Debug (default: Release)
#   ENABLE_ASSERTIONS  ON | OFF (default: OFF)
#   ENABLE_STABLEHLO   ON | OFF (default: ON)
#   JOBS               parallel build jobs (default: number of CPUs)

set -e -o pipefail

TORCH_MLIR_COMMIT="${TORCH_MLIR_COMMIT:-43506726853b35ae9c253aa1d1c61b76ad9b4c13}"
PROJ_URL="${PROJ_URL:-https://github.com/llvm/torch-mlir.git}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BASE_DIR=$SCRIPT_DIR/../..

WORK_DIR="${1:-$BASE_DIR/builds/torch-mlir}"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

SRC_DIR="${SRC_DIR:-$WORK_DIR/torch-mlir}"
VENV_DIR="${VENV_DIR:-$WORK_DIR/venv}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
PYTHON="${PYTHON:-python3}"
TORCH_SPEC="${TORCH_SPEC:-torch==2.4.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
ENABLE_ASSERTIONS="${ENABLE_ASSERTIONS:-OFF}"
ENABLE_STABLEHLO="${ENABLE_STABLEHLO:-ON}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

for tool in git cmake ninja "$PYTHON"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: $tool could not be found. Exiting."
        exit 1
    fi
done


# Fetch only the pinned commit, then shallow-fetch the submodules at the SHAs
# that commit records.
if [ ! -d "$SRC_DIR/.git" ]; then
    git init "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$PROJ_URL"
fi

if [ "$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null)" != "$TORCH_MLIR_COMMIT" ]; then
    git -C "$SRC_DIR" fetch --depth 1 origin "$TORCH_MLIR_COMMIT"
    git -C "$SRC_DIR" checkout --detach FETCH_HEAD
fi

git -C "$SRC_DIR" submodule update --init --depth 1


# Python environment. requirements.txt at this commit pins
# torch==2.5.0.dev20240804, but PyTorch only keeps ~2 months of nightlies, so
# that wheel no longer exists. Instead, mirror the "stable" leg of this
# commit's CI (build_tools/ci/install_python_deps.sh stable), which built
# against the latest stable CPU torch at the time: 2.4.0 (released 2024-07-24).
# The JIT IR importer is compiled against this torch, so keep it matched.
if [ ! -x "$VENV_DIR/bin/python" ]; then
    "$PYTHON" -m venv "$VENV_DIR"
fi
VENV_PYTHON="$VENV_DIR/bin/python"
"$VENV_PYTHON" -m pip install --upgrade pip
"$VENV_PYTHON" -m pip install -r "$SRC_DIR/externals/llvm-project/mlir/python/requirements.txt"
"$VENV_PYTHON" -m pip install "$TORCH_SPEC" --index-url https://download.pytorch.org/whl/cpu
"$VENV_PYTHON" -m pip install -r "$SRC_DIR/build-requirements.txt"
"$VENV_PYTHON" -m pip install -r "$SRC_DIR/test-requirements.txt"


# Optional speedups when available.
EXTRA_CMAKE_ARGS=()
if command -v ccache &> /dev/null; then
    EXTRA_CMAKE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi
if [ "$(uname)" = "Linux" ] && command -v ld.lld &> /dev/null; then
    EXTRA_CMAKE_ARGS+=(-DLLVM_USE_LINKER=lld)
fi


# In-tree build: llvm-project is the main project, torch-mlir is external.
cmake -S "$SRC_DIR/externals/llvm-project/llvm" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DLLVM_ENABLE_ASSERTIONS="$ENABLE_ASSERTIONS" \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_EXTERNAL_PROJECTS=torch-mlir \
    -DLLVM_EXTERNAL_TORCH_MLIR_SOURCE_DIR="$SRC_DIR" \
    -DLLVM_TARGETS_TO_BUILD=host \
    -DMLIR_ENABLE_BINDINGS_PYTHON=ON \
    -DTORCH_MLIR_ENABLE_STABLEHLO="$ENABLE_STABLEHLO" \
    -DPython3_EXECUTABLE="$VENV_PYTHON" \
    -DPython3_FIND_VIRTUALENV=ONLY \
    "${EXTRA_CMAKE_ARGS[@]}"

# Builds torch-mlir (and the parts of LLVM/MLIR it needs), not all of LLVM.
cmake --build "$BUILD_DIR" --target tools/torch-mlir/all -j "$JOBS"


PY_PKG_DIR="$BUILD_DIR/tools/torch-mlir/python_packages/torch_mlir"

# Smoke test.
"$BUILD_DIR/bin/torch-mlir-opt" --version
PYTHONPATH="$PY_PKG_DIR" "$VENV_PYTHON" -c "from torch_mlir import torchscript; print('torch_mlir python bindings OK')"

cat <<EOF

torch-mlir $TORCH_MLIR_COMMIT built in $BUILD_DIR

  torch-mlir-opt:   $BUILD_DIR/bin/torch-mlir-opt
  Python package:   $PY_PKG_DIR
  Python (w/ torch): $VENV_PYTHON

To use it:

    export PATH="$BUILD_DIR/bin:\$PATH"
    export PYTHONPATH="$PY_PKG_DIR:\$PYTHONPATH"
    source "$VENV_DIR/bin/activate"

To rebuild after editing sources under $SRC_DIR:

    cmake --build $BUILD_DIR --target tools/torch-mlir/all -j$JOBS
EOF
