#!/bin/bash
# Link the definitions of the runtime functions an LLVM IR file calls but does not define into it:
# memrefCopy (scripts/lib/memref_copy.c) and, for the llvm.roundeven intrinsics, roundevenf and
# roundeven (scripts/lib/roundeven.c).
#
# Usage: link_memref_copy.sh <target.ll>
#
# Compiles the library to LLVM IR, strips target metadata to match MLIR-generated IR, and links it
# into the given .ll file in-place.

set -e -o pipefail

# Check if docker is available or if the needed binaries are available
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/check_docker.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 <target.ll>"
  exit 1
fi

TARGET_LL="$1"

if [ ! -f "$TARGET_LL" ]; then
  echo "Error: $TARGET_LL not found"
  exit 1
fi

# The IR has to be readable by opt, so the clang on PATH must be of the same LLVM major version
# (Apple's clang is newer than the LLVM that soda-opt is built with). Put the bin directory of
# the LLVM built by scripts/external/setup-llvm.sh first on PATH.
CLANG=clang
CLANG_ENV=""
if [ -z "${DOCKER_RUN}" ] && command -v opt &> /dev/null; then
  OPT_MAJOR="$(opt --version | sed -n 's/.*LLVM version \([0-9]*\)\..*/\1/p')"
  CLANG_MAJOR="$(clang --version | sed -n 's/.*clang version \([0-9]*\)\..*/\1/p' | head -1)"
  if [ "${OPT_MAJOR}" != "${CLANG_MAJOR}" ]; then
    echo "ERROR: the clang on PATH is LLVM ${CLANG_MAJOR} but opt is LLVM ${OPT_MAJOR}, which cannot read its IR." >&2
    echo "       Put the bin directory of the LLVM built by scripts/external/setup-llvm.sh first on PATH." >&2
    exit 1
  fi
fi
# A clang that is not Apple's does not find the macOS SDK on its own.
if [ "$(uname)" = "Darwin" ]; then
  CLANG_ENV="SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}"
fi

# Use a temp directory for intermediate files
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

# link_lib <name> <source.c>: link the compiled source into the target.
link_lib() {
  local name="$1" src="$2"
  local unopt_ll="${TMPDIR}/${name}_unopt.ll" clean_ll="${TMPDIR}/${name}.ll" combined_ll="${TMPDIR}/${name}_combined.ll"

  # Step 1: clang -> unoptimized LLVM IR. No fortify (macOS headers would emit llvm.objectsize and
  # __memcpy_chk, which bambu cannot synthesize) and no builtins (a definition of roundevenf must
  # not become a call to itself).
  env ${CLANG_ENV} $DOCKER_RUN ${CLANG} -S -emit-llvm -O0 -D_FORTIFY_SOURCE=0 -fno-builtin -o "${unopt_ll}" "${src}"

  # Step 2: opt pass (keep at O0 to preserve structure for HLS)
  $DOCKER_RUN opt -S -O0 -o "${clean_ll}" "${unopt_ll}"

  # Step 3: Strip target datalayout and target triple to match MLIR-generated IR
  sed -i.bak '/^target datalayout/d; /^target triple/d' "${clean_ll}" && rm -f "${clean_ll}.bak"

  # Step 4: Link the definitions into the target
  $DOCKER_RUN llvm-link -S "${clean_ll}" "${TARGET_LL}" -o "${combined_ll}"

  # Step 5: Replace the original file
  mv "${combined_ll}" "${TARGET_LL}"
}

# memrefCopy: only when referenced and not already defined
if ! grep -q '@memrefCopy' "$TARGET_LL"; then
  echo "Skipping: no memrefCopy reference found in $TARGET_LL"
elif grep -q 'define.*@memrefCopy' "$TARGET_LL"; then
  echo "Skipping: memrefCopy already defined in $TARGET_LL"
else
  link_lib memref_copy "${SCRIPT_DIR}/lib/memref_copy.c"
fi

# llvm.roundeven: becomes a call of roundevenf/roundeven, which bambu does not have. Call the
# library definitions instead of the intrinsics.
if grep -q '@llvm\.roundeven\.' "$TARGET_LL"; then
  link_lib roundeven "${SCRIPT_DIR}/lib/roundeven.c"
  sed -E -i.bak -e 's/@llvm\.roundeven\.f32/@roundevenf/g' -e 's/@llvm\.roundeven\.f64/@roundeven/g' \
    -e '/^declare .*@roundeven(f)?\(/d' "$TARGET_LL" && rm -f "${TARGET_LL}.bak"
fi
