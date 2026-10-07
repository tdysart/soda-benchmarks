#!/bin/bash
# Run the DPI-free Verilog testbench of bambu dev/panda (--testbench-style=verilog)
# under verilator-sst.
#
# Usage: verilator_sst_devpanda_tb.sh <bambu_dir> <output_results.txt>
#
# <bambu_dir> is the output directory of a bambu run made with
#   --simulate --simulator=VERILATOR --testbench-style=verilog
# i.e. it holds <top>.v, panda_libtech.v, tb_init.mem, tb_expected.mem and
# HLS_output/simulation/{bambu_testbench.v,verilator_verilog_backend/tb_shim_pkg.sv}.
#
# The testbench is a top module whose only port is `clock`: the memory model that
# replaces bambu's DPI host (tb_shim_pkg) lives inside it, and it reads the memory
# images and writes bambu_time_simulation.txt relative to the working directory. So
# verilator-sst only has to toggle the clock; no DPI library and no second process.
#
# verilator-sst's custom-module build takes a single top source file (other modules
# are found by file name), so the shim package, panda_libtech.v, the design and the
# testbench are concatenated into one file, package first.
#
# The result is written to <output_results.txt> as "<1|0> <cycles>" (1 = pass), and the
# script exits non-zero unless the testbench reports a pass.
#
# Runs locally only. Needs a verilator-sst checkout with ENABLE_CUSTOM_MODULE /
# ENABLE_LINK_HANDLING support (branch feature/mdpi-testbench-support of
# tactcomplabs/verilator-sst), Verilator, and SST.
#
# Environment:
#   VERILATOR_SST_SRC     verilator-sst source checkout (required)
#   SST                   sst binary; its directory must also hold sst-config
#                         (default: sst on PATH)
#   TOP_FNAME             name of the synthesized top function (default: from
#                         <bambu_dir>/bambu_results.xml)
#   SST_CYCLES            clock cycles to run (default: bambu's simulated cycle count
#                         from bambu_time_simulation.txt plus 10%, else 40000)
#   VERILATOR_SST_DEVICE  component name (default: bambuTB)

set -e -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <bambu_dir> <output_results.txt>" >&2
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

VERILATOR_SST_DEVICE="${VERILATOR_SST_DEVICE:-bambuTB}"

BAMBU_DIR="$(cd "$1" && pwd)"
OUTPUT_PATH="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
SIM_DIR="$BAMBU_DIR/HLS_output/simulation"
SHIM="$SIM_DIR/verilator_verilog_backend/tb_shim_pkg.sv"
TESTBENCH="$SIM_DIR/bambu_testbench.v"
WORK_DIR="$BAMBU_DIR/verilator-sst"

if [ -z "$TOP_FNAME" ] && [ -f "$BAMBU_DIR/bambu_results.xml" ]; then
  TOP_FNAME="$(awk '/<top_module/ {f=1} f && /name="/ {sub(/.*name="/, ""); sub(/".*/, ""); print; exit}' \
    "$BAMBU_DIR/bambu_results.xml")"
fi
if [ -z "$TOP_FNAME" ]; then
  echo "ERROR: cannot tell the top function; set TOP_FNAME." >&2
  exit 1
fi

for f in "$BAMBU_DIR/$TOP_FNAME.v" "$BAMBU_DIR/panda_libtech.v" "$TESTBENCH" "$SHIM" \
         "$BAMBU_DIR/tb_init.mem" "$BAMBU_DIR/tb_expected.mem"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f not found; run bambu with --testbench-style=verilog first." >&2
    exit 1
  fi
done

# bambu's own run left bambu_time_simulation.txt as "<start>|<end>," then the return code.
NATIVE_CYCLES=""
if [ -f "$BAMBU_DIR/bambu_time_simulation.txt" ]; then
  NATIVE_CYCLES="$(awk -F'[|,]' 'NR==1 && $2 != "" {print int(($2 - $1) / 2)}' "$BAMBU_DIR/bambu_time_simulation.txt")"
fi
if [ -z "$SST_CYCLES" ]; then
  if [ -n "$NATIVE_CYCLES" ] && [ "$NATIVE_CYCLES" -gt 0 ]; then
    SST_CYCLES=$(( NATIVE_CYCLES + NATIVE_CYCLES / 10 + 100 ))
  else
    SST_CYCLES=40000
  fi
fi

rm -rf "$WORK_DIR/verilog"
mkdir -p "$WORK_DIR/verilog"
cat "$SHIM" "$BAMBU_DIR/panda_libtech.v" "$BAMBU_DIR/$TOP_FNAME.v" "$TESTBENCH" \
  > "$WORK_DIR/verilog/sst_top.sv"

# --timescale-override 1ps/1ps matches what bambu's own Verilator runs use; the
# testbench's cycle counting assumes it (see V2023_XML_TESTBENCH.md in the verilator-sst
# checkout). The defines select the DPI-free testbench and bambu's 64-bit pointers.
cmake -S "$VERILATOR_SST_SRC" -B "$WORK_DIR/build" \
  -DENABLE_CUSTOM_MODULE=ON \
  -DVERILOG_SOURCE_DIR="$WORK_DIR/verilog" \
  -DVERILOG_DEVICE="$VERILATOR_SST_DEVICE" \
  -DVERILOG_TOP=bambu_testbench \
  -DVERILOG_TOP_SOURCES=sst_top.sv \
  -DVERILATOR_OPTIONS="-Wno-fatal -Wno-lint -sv --no-timing --timescale-override 1ps/1ps --x-assign fast --x-initial fast --noassert +define+BAMBU_TB_VERILOG +define+__M64 +define+__BAMBU_SIM__" \
  -DENABLE_LINK_HANDLING=ON \
  -DCLOCK_PORT_NAME=clock \
  2>&1 | tee "$WORK_DIR/cmake-config.log"

cmake --build "$WORK_DIR/build" -j "$(nproc 2>/dev/null || sysctl -n hw.ncpu)" \
  2>&1 | tee "$WORK_DIR/build.log"

# The testbench opens tb_init.mem / tb_expected.mem and writes bambu_time_simulation.txt
# relative to the working directory. Remove the previous result so a stale one is never
# reported.
rm -f "$BAMBU_DIR/bambu_time_simulation.txt"

# The SST log repeats a $finish notice for every cycle after the testbench completes;
# keep it in a file and show only the testbench's own messages.
(cd "$BAMBU_DIR" && "$SST" "$SCRIPT_DIR/verilator_sst_tb.py" -- \
  --build-dir "$WORK_DIR/build" \
  --device "$VERILATOR_SST_DEVICE" \
  --cycles "$SST_CYCLES") > "$WORK_DIR/sst-run.log" 2>&1
grep -E "Sim:|ERROR" "$WORK_DIR/sst-run.log" | grep -v '\$finish' | awk '!seen[$0]++' || true

RESULT="$BAMBU_DIR/bambu_time_simulation.txt"
if [ ! -s "$RESULT" ] || [ "$(awk 'NR==2 {print $1}' "$RESULT")" = "" ]; then
  echo "ERROR: the testbench did not finish in $SST_CYCLES cycles; raise SST_CYCLES (see $WORK_DIR/sst-run.log)." >&2
  exit 1
fi

RETURN_CODE="$(awk 'NR==2 {print $1}' "$RESULT")"
CYCLES="$(awk -F'[|,]' 'NR==1 {print int(($2 - $1) / 2)}' "$RESULT")"
if [ "$RETURN_CODE" = "0" ]; then
  echo "1 $CYCLES" > "$OUTPUT_PATH"
  echo "verilator-sst: PASS in $CYCLES cycles ($OUTPUT_PATH)"
else
  echo "0 $CYCLES" > "$OUTPUT_PATH"
  echo "ERROR: testbench reported a failure under SST (return code $RETURN_CODE); see $WORK_DIR/sst-run.log" >&2
  exit 1
fi
