#!/bin/bash
# Synthesize a C kernel with bambu dev/panda and run its C testbench through the DPI-free
# Verilog testbench of --testbench-style=verilog.
#
# Usage: c_to_verilog_devpanda_tb.sh <input.c> <testbench.c> <output.v>
#
# Unlike c_to_verilog_verilog_tb.sh (the XML test vector flow of the autotools port), this takes
# the example's C testbench, the same file the MDPI flow uses: it is run natively to record the
# memory images and the reference results, and the Verilog testbench replays them. See
# MACOS_PORT.md in the PandA-bambu branch spike/devpanda-macos-testbench.
#
# <input.c> must declare its interfaces with the dev/panda pragma syntax
# (#pragma HLS interface port=P0 mode=m_axi offset=direct bundle=gmem0); the older
# `#pragma HLS_interface P0 m_axi direct` is ignored.
#
# Runs locally only (no docker). Outputs land next to <output.v>: bambu's forward_kernel.v copied
# to 06_verilog.v and, when simulating, 07_results.txt ("<1|0><TAB><cycles>") together with the
# testbench (HLS_output/simulation/), the memory images (tb_init.mem, tb_expected.mem) and
# bambu_time_simulation.txt, which verilator_sst_devpanda_tb.sh needs.
#
# Environment:
#   BAMBU_DEVPANDA        a bambu built from dev/panda with --testbench-style (default: bambu on
#                         PATH); its installation directory is the parent of its bin directory
#   BAMBU_DEVICE          (default: nangate45, as c_to_verilog.sh)
#   BAMBU_CLOCK_PERIOD    (default: 5)
#   BAMBU_MEMPOLICY       (default: NO_BRAM)
#   BAMBU_COMPILER        bambu --compiler (default: I386_CLANG19)
#   BAMBU_M               word size flag (default: -m64 on macOS, where clang has no 32-bit target)
#   CLANG_BIN             directory with the clang named by --compiler (default: Homebrew llvm@19)
#   BAMBU_RUN_SIMULATION  true to also simulate with Verilator (default: false)
#   BAMBU_TOP             top function (default: forward_kernel)

set -e -o pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <input.c> <testbench.c> <output.v>" >&2
  exit 1
fi

BAMBU_DEVPANDA="${BAMBU_DEVPANDA:-bambu}"
BAMBU_DEVICE="${BAMBU_DEVICE:-nangate45}"
BAMBU_MEMPOLICY="${BAMBU_MEMPOLICY:-NO_BRAM}"
BAMBU_CLOCK_PERIOD="${BAMBU_CLOCK_PERIOD:-5}"
BAMBU_COMPILER="${BAMBU_COMPILER:-I386_CLANG19}"
BAMBU_RUN_SIMULATION="${BAMBU_RUN_SIMULATION:-false}"
BAMBU_TOP="${BAMBU_TOP:-forward_kernel}"
if [ -z "${BAMBU_M+x}" ]; then
  if [ "$(uname)" = "Darwin" ]; then BAMBU_M="-m64"; else BAMBU_M=""; fi
fi
CLANG_BIN="${CLANG_BIN:-/opt/homebrew/opt/llvm@19/bin}"

if ! command -v "$BAMBU_DEVPANDA" &> /dev/null; then
  echo "ERROR: $BAMBU_DEVPANDA could not be found. Set BAMBU_DEVPANDA to a bambu built from dev/panda." >&2
  exit 1
fi
BAMBU_DEVPANDA="$(command -v "$BAMBU_DEVPANDA")"
# Capture the help first: grep -q exiting early would fail the pipe (pipefail).
BAMBU_HELP="$("$BAMBU_DEVPANDA" --help 2>&1 || true)"
if ! grep -q -- "--testbench-style" <<< "$BAMBU_HELP"; then
  echo "ERROR: $BAMBU_DEVPANDA has no --testbench-style option; build bambu from" >&2
  echo "       branch spike/devpanda-macos-testbench of tdysart/PandA-bambu." >&2
  exit 1
fi

# An installed bambu finds its libraries from these (settings.sh sets them, but it needs GNU
# readlink -e, which macOS lacks).
BAMBU_HLS="${BAMBU_HLS:-$(cd "$(dirname "$BAMBU_DEVPANDA")/.." && pwd)}"
export BAMBU_HLS
export BAMBU_HLS_BACKEND_PATH="${BAMBU_HLS_BACKEND_PATH:-$BAMBU_HLS}"
export PATH="$CLANG_BIN:$PATH"

# The backend scripts bambu generates use GNU readlink -e and gawk; shim them on macOS.
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
command -v greadlink &> /dev/null && ln -sf "$(command -v greadlink)" "$SHIM_DIR/readlink"
command -v gawk &> /dev/null && ln -sf "$(command -v gawk)" "$SHIM_DIR/awk"
export PATH="$SHIM_DIR:$PATH"

# Homebrew's clang does not find the macOS SDK on its own.
if [ "$(uname)" = "Darwin" ]; then
  export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
fi

TESTBENCH="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
mkdir -p "$(dirname "$3")"
OUTPUT_DIR="$(cd "$(dirname "$3")" && pwd)"

cp "$1" "$OUTPUT_DIR/input.c"
pushd "$OUTPUT_DIR"

SIMULATION_ARGS=""
if [ "$BAMBU_RUN_SIMULATION" = "true" ]; then
  SIMULATION_ARGS="--simulate --simulator=VERILATOR --testbench-style=verilog --generate-tb=$TESTBENCH"
fi

# dev/panda dropped -lm, --soft-float, --verilator-parallel and -v3.
"$BAMBU_DEVPANDA" $BAMBU_M --print-dot \
	--compiler=$BAMBU_COMPILER \
	--device=$BAMBU_DEVICE \
	--clock-period=$BAMBU_CLOCK_PERIOD \
	--experimental-setup=BAMBU-BALANCED-MP \
	--channels-number=2 \
	--memory-allocation-policy=$BAMBU_MEMPOLICY \
	--disable-function-proxy \
	--generate-interface=INFER \
	$SIMULATION_ARGS \
	--top-fname=$BAMBU_TOP \
	input.c 2>&1 | tee bambu-log

cp $BAMBU_TOP.v 06_verilog.v

# bambu_time_simulation.txt is "<start>|<end>," on its first line and the return code on the
# second: write "<1|0><TAB><cycles>", the format of the other pure-Verilog testbench flows.
if [ "$BAMBU_RUN_SIMULATION" = "true" ]; then
  if [ -s bambu_time_simulation.txt ]; then
    awk -F'[|,]' 'NR==1 {cycles = int(($2 - $1) / 2)} NR==2 {rc = $1}
                  END {printf "%d\t%d\n", (rc == "0" ? 1 : 0), cycles}' bambu_time_simulation.txt > 07_results.txt
    if [ "$(cut -f1 07_results.txt)" != "1" ]; then
      echo "ERROR: the testbench reported a failure: $(cat 07_results.txt)" >&2
      exit 1
    fi
  else
    echo "ERROR: no bambu_time_simulation.txt; the simulation did not finish." >&2
    exit 1
  fi
fi

popd
