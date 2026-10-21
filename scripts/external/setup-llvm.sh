#!/bin/bash

# Build the one LLVM 19.1.5 (clang and MLIR) that every tool of the flow uses:
#
#   soda-opt     needs the MLIR it was tested with (19.1.5), including MLIR's test-pass libraries
#                (MLIRAffineTransformsTestPasses, MLIRLinalgTestPasses, MLIRTilingInterfaceTestPasses)
#                and FileCheck/lit for its tests. Those exist only when MLIR is built with
#                MLIR_INCLUDE_TESTS=ON, which distribution packages such as Homebrew's llvm@19 do
#                not do.
#   bambu        (the bambu branch, --compiler=I386_CLANG19) needs clang 19 and an LLVM with RTTI,
#                because its clang plugins derive from LLVM's classes, plus llvm-ar and llvm-ranlib.
#   mlir-opt, mlir-translate, opt, llc, llvm-link   used by the scripts of this repo.
#
# Verified on macOS arm64 (2026-10-21): builds in about 15 minutes on 14 cores (a further minute
# to add the Python bindings), using 14 GB for install/, 29 GB for build/ and 2 GB for the source.
# All checks at the end pass; soda-opt built against it passes all 41 of its lit tests, and bambu
# built with its clang runs the soda-benchmarks flow (see docs/FlowSurvey.md).
#
# Usage:
#   ./scripts/external/setup-llvm.sh [WORK_DIR]
#
# WORK_DIR defaults to builds/llvm in this repo. Layout created inside it:
#   llvm-project/   source checkout at the LLVM tag (skipped when SRC_DIR is given)
#   build/          CMake/Ninja build tree
#   install/        the result: bin/ lib/ include/ lib/cmake/{llvm,mlir,clang}
#
# Overridable environment variables:
#   LLVM_TAG           tag to build (default: llvmorg-19.1.5, the commit soda-opt's README names)
#   SRC_DIR            an existing llvm-project checkout at that tag, to skip the download. For
#                      example ~/SODA-OPT/llvm/llvm-project, which is already at llvmorg-19.1.5
#   BUILD_DIR, INSTALL_DIR   override the locations above
#   BUILD_TYPE         Release | RelWithDebInfo | Debug (default: RelWithDebInfo, as soda-opt's
#                      build_llvm.sh)
#   ENABLE_ASSERTIONS  ON | OFF (default: ON, as soda-opt's build_llvm.sh). Everything that builds
#                      against this install (bambu's plugins, soda-opt) must use its headers, which
#                      the ABI-breaking-checks setting changes, so do not mix installs. With ON,
#                      bambu's clang plugins need two fixes that the bambu branch carries
#                      (plugin_ASTAnalyzer.cpp passed DiagID 0 to RequireCompleteType, and
#                      TreeHeightReduction.hpp called isFast() on any floating-point instruction);
#                      both abort only in an LLVM with assertions. A bambu without them needs OFF.
#   SHARED             ON | OFF (default: ON): libLLVM, libclang-cpp and libMLIR as shared
#                      libraries that the tools link to. bambu's clang
#                      plugins are linked with -undefined dynamic_lookup and take LLVM's symbols
#                      from the process that loads them, which is what this layout is known to work
#                      with. With OFF the symbols are exported from the clang executable instead
#                      (LLVM_EXPORT_SYMBOLS_FOR_PLUGINS); untested.
#   TARGETS            LLVM_TARGETS_TO_BUILD (default: host). bambu's macOS flow is -m64 only;
#                      use "host;X86" or "all" if something needs another target.
#   PYTHON_BINDINGS    ON | OFF (default: OFF). ON builds MLIR's Python bindings, which soda-opt's
#                      python/simple-parse.py test needs (without them that one of its 41 lit tests
#                      is unsupported). LLVM 19.1.5 needs numpy <= 1.26, pybind11 <= 2.10.3 and
#                      PyYAML in the Python that PYTHON points to (mlir/python/requirements.txt);
#                      the venv that setup-torch-mlir.sh creates has exactly those.
#   PYTHON             interpreter for the bindings and for lit (default: python3)
#   JOBS               parallel build jobs (default: number of CPUs)

set -e -o pipefail

LLVM_TAG="${LLVM_TAG:-llvmorg-19.1.5}"
LLVM_URL="${LLVM_URL:-https://github.com/llvm/llvm-project.git}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BASE_DIR=$SCRIPT_DIR/../..

WORK_DIR="${1:-$BASE_DIR/builds/llvm}"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

SRC_DIR="${SRC_DIR:-$WORK_DIR/llvm-project}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
INSTALL_DIR="${INSTALL_DIR:-$WORK_DIR/install}"
BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}"
ENABLE_ASSERTIONS="${ENABLE_ASSERTIONS:-ON}"
SHARED="${SHARED:-ON}"
TARGETS="${TARGETS:-host}"
PYTHON_BINDINGS="${PYTHON_BINDINGS:-OFF}"
PYTHON="${PYTHON:-python3}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

for tool in git cmake ninja "$PYTHON"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: $tool could not be found. Exiting."
        exit 1
    fi
done


# Source: shallow fetch of the tag only, unless an existing checkout was given.
if [ ! -d "$SRC_DIR/llvm" ]; then
    git init "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$LLVM_URL"
    git -C "$SRC_DIR" fetch --depth 1 origin "refs/tags/$LLVM_TAG:refs/tags/$LLVM_TAG"
    git -C "$SRC_DIR" checkout --detach "$LLVM_TAG"
fi
SRC_TAG="$(git -C "$SRC_DIR" describe --tags --exact-match 2>/dev/null || true)"
if [ "$SRC_TAG" != "$LLVM_TAG" ]; then
    echo "ERROR: $SRC_DIR is at '${SRC_TAG:-no tag}', not $LLVM_TAG."
    exit 1
fi


# Shared or static LLVM.
SHARED_ARGS=()
if [ "$SHARED" = "ON" ]; then
    SHARED_ARGS+=(-DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON
                  -DCLANG_LINK_CLANG_DYLIB=ON -DMLIR_LINK_MLIR_DYLIB=ON)
else
    SHARED_ARGS+=(-DLLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON)
fi

# On macOS use Apple's clang, so the libc++ of the compiler that builds this is the one that
# bambu's plugins (also built with Apple clang) are loaded into.
HOST_ARGS=()
if [ "$(uname)" = "Darwin" ]; then
    HOST_ARGS+=(-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++)
else
    HOST_ARGS+=(-DLLVM_USE_LINKER=lld)
    command -v ld.lld &> /dev/null || HOST_ARGS=()
fi

# Optional speedup when available.
if command -v ccache &> /dev/null; then
    HOST_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

PYTHON_ARGS=(-DMLIR_ENABLE_BINDINGS_PYTHON="$PYTHON_BINDINGS")
if [ "$PYTHON_BINDINGS" = "ON" ]; then
    PYTHON_ARGS+=(-DPython3_EXECUTABLE="$(command -v "$PYTHON")")
fi

# What each option is for:
#   LLVM_ENABLE_PROJECTS="clang;mlir"   clang for bambu, MLIR for soda-opt and the scripts
#   LLVM_ENABLE_RTTI=ON                 bambu's clang plugins need it
#   MLIR_INCLUDE_TESTS=ON               builds MLIR's test-pass libraries that soda-opt links
#   LLVM_INSTALL_UTILS=ON               installs FileCheck, not, count (soda-opt's lit tests)
#   LLVM_BUILD_TOOLS=ON                 llvm-ar, llvm-ranlib, llvm-objcopy, opt, llc, llvm-link
cmake -S "$SRC_DIR/llvm" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_ENABLE_PROJECTS="clang;mlir" \
    -DLLVM_TARGETS_TO_BUILD="$TARGETS" \
    -DLLVM_ENABLE_ASSERTIONS="$ENABLE_ASSERTIONS" \
    -DLLVM_ENABLE_RTTI=ON \
    -DLLVM_ENABLE_LLD=OFF \
    -DLLVM_INCLUDE_TOOLS=ON \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INSTALL_UTILS=ON \
    -DLLVM_INCLUDE_TESTS=ON \
    -DMLIR_INCLUDE_TESTS=ON \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    "${SHARED_ARGS[@]}" \
    "${PYTHON_ARGS[@]}" \
    "${HOST_ARGS[@]}"

cmake --build "$BUILD_DIR" -j "$JOBS"
cmake --install "$BUILD_DIR"


# Checks: the properties the other tools rely on.
fail=0
check() { if ! eval "$2"; then echo "CHECK FAILED: $1"; fail=1; else echo "ok: $1"; fi; }

LLVM_CONFIG="$INSTALL_DIR/bin/llvm-config"
check "version is ${LLVM_TAG#llvmorg-}" '[ "$("$LLVM_CONFIG" --version)" = "${LLVM_TAG#llvmorg-}" ]'
check "RTTI is on"                      '[ "$("$LLVM_CONFIG" --has-rtti)" = "YES" ]'
check "clang is installed"              '"$INSTALL_DIR/bin/clang" --version | grep -q "version 19"'
check "mlir-opt and mlir-translate"     '[ -x "$INSTALL_DIR/bin/mlir-opt" ] && [ -x "$INSTALL_DIR/bin/mlir-translate" ]'
check "opt, llc, llvm-link"             '[ -x "$INSTALL_DIR/bin/opt" ] && [ -x "$INSTALL_DIR/bin/llc" ] && [ -x "$INSTALL_DIR/bin/llvm-link" ]'
check "llvm-ar and llvm-ranlib"         '[ -x "$INSTALL_DIR/bin/llvm-ar" ] && [ -x "$INSTALL_DIR/bin/llvm-ranlib" ]'
check "FileCheck, not, count"           '[ -x "$INSTALL_DIR/bin/FileCheck" ] && [ -x "$INSTALL_DIR/bin/not" ] && [ -x "$INSTALL_DIR/bin/count" ]'
for lib in MLIRAffineTransformsTestPasses MLIRLinalgTestPasses MLIRTilingInterfaceTestPasses MLIRTestDialect; do
    check "lib$lib.a (soda-opt links it)" '[ -f "$INSTALL_DIR/lib/lib$lib.a" ]'
done
check "llvm-lit in the build tree"      '[ -x "$BUILD_DIR/bin/llvm-lit" ]'
check "MLIR cmake package"              '[ -f "$INSTALL_DIR/lib/cmake/mlir/MLIRConfig.cmake" ]'
if [ "$fail" != 0 ]; then
    echo "Some checks failed; see above."
    exit 1
fi

cat <<EOF

LLVM $LLVM_TAG (clang, MLIR) built and installed in $INSTALL_DIR

To use it:

    export PATH="$INSTALL_DIR/bin:\$PATH"

soda-opt (in a new build directory, since its CMake cache holds the old LLVM; add
-DPython3_EXECUTABLE=<python> -DPython3_FIND_VIRTUALENV=ONLY when built with PYTHON_BINDINGS=ON,
then \`ninja soda-opt check-soda\`, since the default target does not build soda-opt):

    cmake -G Ninja -S <soda-opt> -B <build> \\
        -DMLIR_DIR=$INSTALL_DIR/lib/cmake/mlir \\
        -DLLVM_DIR=$INSTALL_DIR/lib/cmake/llvm \\
        -DLLVM_EXTERNAL_LIT=$BUILD_DIR/bin/llvm-lit

The bambu branch (see MACOS_PORT.md): build it with this clang, i.e. with $INSTALL_DIR/bin first on
PATH, SDKROOT=\$(xcrun --show-sdk-path) exported (this clang does not find the macOS SDK on its own),
and -DPANDA_LIBBAMBU_COMPILER=I386_CLANG19. The soda-benchmarks scripts then take clang-19 from PATH
(set CLANG_BIN to override).
EOF
