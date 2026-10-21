#!/bin/bash

# Put the tools of the soda-benchmarks flow on PATH. Source it, do not run it:
#
#   source scripts/soda_env.sh
#
# It only adds to PATH and sets SDKROOT, and it skips directories that do not exist, so it works
# while the tools are only partly built.
#
# The flow uses one LLVM 19.1.5 (clang, MLIR, RTTI, MLIR test libraries; built by
# scripts/external/setup-llvm.sh). mlir-opt, mlir-translate, opt and clang come from it, soda-opt is
# built against it, and the bambu branch is built with its clang. Where things are expected (the
# defaults assume the layout of docs/ModelConversionTools.md, with this repository next to the
# others; override any of them in the environment before sourcing):
#
#   SODA_ROOT      directory that holds this repository and the tool builds (default: the
#                  directory above this repository)
#   LLVM_FULL      the setup-llvm.sh work directory         ($SODA_ROOT/llvm-19.1.5-full)
#                    install/bin           clang, mlir-opt, mlir-translate, opt, llvm-ar, FileCheck
#                    soda-opt-build/bin    soda-opt (built against that LLVM)
#   BAMBU_INSTALL  install of the bambu branch              ($SODA_ROOT/panda/install-devpanda-llvm-full)
#   TF_TOOLS       tf-opt, tf-mlir-translate, ...           ($SODA_ROOT/tensorflow/bin)
#   TORCH_MLIR_BIN torch-mlir-opt                           ($SODA_ROOT/torch-mlir/build/bin)
#   SST_HOME       optional: an SST install whose core-install/bin and elements-install/bin
#                  hold sst (for the 08_sst_results.txt targets); not set by default
#
# Python is not touched: the PyTorch examples also need torch-mlir's venv activated and its package
# on PYTHONPATH, and the TensorFlow ones a Python with TensorFlow first on PATH (see
# docs/PureVerilogTestbench.md and docs/FlowSurvey.md).

# The directory of this file, when sourced from bash or from zsh.
_soda_src="${BASH_SOURCE[0]-}"
[ -n "$_soda_src" ] || _soda_src="$0"
_soda_repo="$(cd "$(dirname "$_soda_src")/.." && pwd)"

SODA_ROOT="${SODA_ROOT:-$(dirname "$_soda_repo")}"
LLVM_FULL="${LLVM_FULL:-$SODA_ROOT/llvm-19.1.5-full}"
BAMBU_INSTALL="${BAMBU_INSTALL:-$SODA_ROOT/panda/install-devpanda-llvm-full}"
TF_TOOLS="${TF_TOOLS:-$SODA_ROOT/tensorflow/bin}"
TORCH_MLIR_BIN="${TORCH_MLIR_BIN:-$SODA_ROOT/torch-mlir/build/bin}"

# Put the existing directories among the arguments in front of PATH, in the order given.
_soda_prepend() {
    local d new=""
    for d in "$@"; do
        [ -d "$d" ] && new="${new:+$new:}$d"
    done
    [ -n "$new" ] && PATH="$new:$PATH"
}

_soda_gnubin=""
if command -v brew &> /dev/null; then
    _soda_gnubin="$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin"
elif [ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]; then
    _soda_gnubin=/opt/homebrew/opt/coreutils/libexec/gnubin
fi

_soda_prepend \
    "$_soda_gnubin" \
    "$LLVM_FULL/install/bin" \
    "$LLVM_FULL/soda-opt-build/bin" \
    "$BAMBU_INSTALL/bin" \
    "$TF_TOOLS" \
    "$TORCH_MLIR_BIN"

if [ -n "${SST_HOME-}" ]; then
    _soda_prepend "$SST_HOME/elements-install/bin" "$SST_HOME/core-install/bin"
fi
export PATH

# The LLVM's clang does not find the macOS SDK on its own.
if [ "$(uname)" = "Darwin" ]; then
    SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
    export SDKROOT
fi

unset -f _soda_prepend
unset _soda_src _soda_repo _soda_gnubin
