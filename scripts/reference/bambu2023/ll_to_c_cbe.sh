#!/bin/bash
# Translate soda-opt's LLVM IR into C with the llvm-cbe C backend.
#
# Usage: ll_to_c_cbe.sh <input.ll> <output.c>
#
# Older bambu releases (e.g. v2023.1, whose only front end is I386_CLANG13)
# cannot parse the LLVM 19 IR soda-opt emits (opaque pointers, memory(...)
# attributes). Going through C lets them synthesize the kernel anyway.
#
# llvm-cbe emits every bare-pointer memref argument as `void*`. bambu's XML
# testbench needs typed pointers to lay out the test vectors, so the kernel's
# declaration and definition are retyped to CBE_PTR_TYPE (the body already
# casts every use, so this does not change the computation).
#
# Runs locally only (no docker): the SODA image does not ship llvm-cbe. Build
# https://github.com/JuliaHubOSS/llvm-cbe at a commit matching your LLVM
# (21569b994b is the last one targeting LLVM 19.1).
#
# Environment:
#   LLVM_CBE      llvm-cbe binary (default: llvm-cbe on PATH)
#   KERNEL_NAME   function to retype (default: forward_kernel)
#   CBE_PTR_TYPE  element type of the kernel's pointer arguments (default: float)

set -e -o pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <input.ll> <output.c>" >&2
  exit 1
fi

LLVM_CBE="${LLVM_CBE:-llvm-cbe}"
KERNEL_NAME="${KERNEL_NAME:-forward_kernel}"
CBE_PTR_TYPE="${CBE_PTR_TYPE:-float}"

if ! command -v "$LLVM_CBE" &> /dev/null; then
  echo "ERROR: $LLVM_CBE could not be found. Set LLVM_CBE or add llvm-cbe to PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "$2")"
CBE_RAW="${2%.c}_cbe.c"
"$LLVM_CBE" "$1" -o "$CBE_RAW"

# Only the kernel's own declaration and definition lines start with
# `void <kernel>(`; call sites and other functions are left alone.
sed -E "/^void ${KERNEL_NAME}\(/ s/void\* (_[0-9]+)/${CBE_PTR_TYPE}* \1/g" "$CBE_RAW" > "$2"

if ! grep -qE "^void ${KERNEL_NAME}\(${CBE_PTR_TYPE}\* _" "$2"; then
  echo "ERROR: could not find/retype ${KERNEL_NAME} in $2" >&2
  exit 1
fi
