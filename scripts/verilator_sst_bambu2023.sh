#!/bin/bash
# Build a bambu v2023.1 self-contained (non-DPI) testbench into a
# verilator-sst component and run it under SST.
#
# Usage: verilator_sst_bambu2023.sh <bambu_dir/06_verilog.v> <output_results.txt>
#
# <bambu_dir> is an output directory of c_to_verilog_bambu2023.sh. Its
# forward_kernel.v and HLS_output/simulation/testbench_forward_kernel_tb.v are
# staged into <bambu_dir>/verilator-sst/verilog (on their own: bambu's
# 06_verilog.v copy would duplicate every module), built with verilator-sst's
# custom-module path, and run with verilator_sst_bambu2023_tb.py.
#
# The testbench writes its result to <bambu_dir>/results.txt (the absolute
# path bambu baked into it); that file is removed before the run and copied to
# <output_results.txt> after, so a stale result is never reported. Exits
# non-zero unless the testbench reports a pass.
#
# Runs locally only (no docker). Needs a verilator-sst checkout with
# ENABLE_CUSTOM_MODULE/ENABLE_LINK_HANDLING support (branch
# feature/mdpi-testbench-support of tactcomplabs/verilator-sst).
#
# Environment:
#   VERILATOR_SST_SRC     verilator-sst source checkout (required)
#   SST                   sst binary; its directory must also hold sst-config
#                         (default: sst on PATH)
#   SST_CYCLES            clock cycles to run (default: bambu's simulated
#                         count from 07_results.txt plus 10%, else 40000)
#   VERILATOR_SST_DEVICE  component name (default: forwardKernelTB)

set -e -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <bambu_dir/06_verilog.v> <output_results.txt>" >&2
  exit 1
fi

if [ -z "$VERILATOR_SST_SRC" ] || [ ! -f "$VERILATOR_SST_SRC/CMakeLists.txt" ]; then
  echo "ERROR: set VERILATOR_SST_SRC to a verilator-sst source checkout." >&2
  exit 1
fi

SST="${SST:-sst}"
if ! command -v "$SST" &> /dev/null; then
  echo "ERROR: $SST could not be found. Set SST to the sst binary." >&2
  exit 1
fi
# verilator-sst's CMake looks up sst and sst-config on PATH.
SST="$(command -v "$SST")"
PATH="$(dirname "$SST"):$PATH"
export PATH

VERILATOR_SST_DEVICE="${VERILATOR_SST_DEVICE:-forwardKernelTB}"

BAMBU_DIR="$(cd "$(dirname "$1")" && pwd)"
OUTPUT_PATH="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
TESTBENCH="$BAMBU_DIR/HLS_output/simulation/testbench_forward_kernel_tb.v"
WORK_DIR="$BAMBU_DIR/verilator-sst"

for f in "$BAMBU_DIR/forward_kernel.v" "$TESTBENCH"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f not found; run c_to_verilog_bambu2023.sh first." >&2
    exit 1
  fi
done

if [ -z "$SST_CYCLES" ]; then
  if [ -f "$BAMBU_DIR/07_results.txt" ]; then
    NATIVE_CYCLES="$(awk 'NR==1 {print $2}' "$BAMBU_DIR/07_results.txt")"
    SST_CYCLES=$(( NATIVE_CYCLES + NATIVE_CYCLES / 10 ))
  else
    SST_CYCLES=40000
  fi
fi

rm -rf "$WORK_DIR/verilog"
mkdir -p "$WORK_DIR/verilog"
cp "$BAMBU_DIR/forward_kernel.v" "$TESTBENCH" "$WORK_DIR/verilog/"

# --timescale-override 1ps/1ps matches what bambu's own Verilator runs use; the
# testbench's timing constants assume it (see V2023_XML_TESTBENCH.md in the
# verilator-sst checkout).
cmake -S "$VERILATOR_SST_SRC" -B "$WORK_DIR/build" \
  -DENABLE_CUSTOM_MODULE=ON \
  -DVERILOG_SOURCE_DIR="$WORK_DIR/verilog" \
  -DVERILOG_DEVICE="$VERILATOR_SST_DEVICE" \
  -DVERILOG_TOP=forward_kernel_tb \
  -DVERILOG_TOP_SOURCES=testbench_forward_kernel_tb.v \
  -DVERILATOR_OPTIONS="-Wno-fatal -Wno-lint --timescale-override 1ps/1ps" \
  -DENABLE_LINK_HANDLING=ON \
  -DCLOCK_PORT_NAME=clock \
  2>&1 | tee "$WORK_DIR/cmake-config.log"

cmake --build "$WORK_DIR/build" -j "$(nproc 2>/dev/null || sysctl -n hw.ncpu)" \
  2>&1 | tee "$WORK_DIR/build.log"

rm -f "$BAMBU_DIR/results.txt"

# The SST log repeats a $finish notice for every cycle after the testbench
# completes; keep it in a file and show only the testbench's own messages.
"$SST" "$SCRIPT_DIR/verilator_sst_bambu2023_tb.py" -- \
  --build-dir "$WORK_DIR/build" \
  --device "$VERILATOR_SST_DEVICE" \
  --cycles "$SST_CYCLES" > "$WORK_DIR/sst-run.log" 2>&1
grep -E "Simulation|ERROR" "$WORK_DIR/sst-run.log" | grep -v '\$finish' || true

if [ ! -s "$BAMBU_DIR/results.txt" ]; then
  echo "ERROR: the testbench wrote no results in $SST_CYCLES cycles; raise SST_CYCLES (see $WORK_DIR/sst-run.log)." >&2
  exit 1
fi
cp "$BAMBU_DIR/results.txt" "$OUTPUT_PATH"

if [ "$(awk 'NR==1 {print $1}' "$OUTPUT_PATH")" != "1" ]; then
  echo "ERROR: testbench reported a failure under SST: $(cat "$OUTPUT_PATH")" >&2
  exit 1
fi
echo "verilator-sst: PASS in $(awk 'NR==1 {print $2}' "$OUTPUT_PATH") cycles ($OUTPUT_PATH)"
