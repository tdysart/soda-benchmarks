#!/bin/bash
# The verilator-sst CMake options for bambu's Verilog, shared by every build of a verilator-sst model
# of it: verilator_sst_devpanda_tb.sh here (bambu's whole testbench, replayed under SST) and
# soda-sst-system's scripts/build_kernel.sh (the kernel alone, driven through its ports). Both
# verilate the same Verilog, so they verilate it the same way, apart from what each sets itself (below).
# Source it, do not run it:
#
#   . verilator_sst_options.sh
#   cmake -S "$VERILATOR_SST_SRC" -B build "${VERILATOR_SST_CMAKE_OPTIONS[@]}" \
#     -DVERILATOR_OPTIONS="$BAMBU_VERILATOR_OPTIONS --x-initial ..." \
#     -DVERILOG_SOURCE_DIR=... -DVERILOG_DEVICE=... -DVERILOG_TOP=... -DVERILOG_TOP_SOURCES=... \
#     -DENABLE_LINK_HANDLING=...
#
# What each build sets itself is what differs between them on purpose: the sources and the top module,
# the device name, whether SST links drive the model (ENABLE_LINK_HANDLING), any define of its own (the
# testbench's +define+BAMBU_TB_VERILOG), and --x-initial, the start value of a register the design
# never sets:
#   fast     whatever was in memory. bambu's own Verilator runs use it, and its testbench needs it: with
#            unique the testbench never finishes, so verilator_sst_devpanda_tb.sh uses fast
#   unique   random, from a new seed every run (verilator-sst sets Verilator's randReset(2)), so a run
#            that passes shows the kernel does not depend on such a register; soda-sst-system's
#            build_kernel.sh uses it

# Verilator's options for bambu's Verilog:
#   -Wno-fatal -Wno-lint -sv       bambu's Verilog is SystemVerilog and is not lint-clean
#   --no-timing --noassert         no delays or assertions: SST's clock drives the model
#   --timescale-override 1ps/1ps   what bambu's own Verilator runs use; the testbench's cycle count
#                                  assumes it
#   --x-assign fast                an X assigned in the design takes whatever value is fastest
#   +define+__M64                  bambu's 64-bit pointers (bambu -m64)
#   +define+__BAMBU_SIM__          bambu's simulation-only Verilog
BAMBU_VERILATOR_OPTIONS="-Wno-fatal -Wno-lint -sv --no-timing --timescale-override 1ps/1ps --x-assign fast --noassert +define+__M64 +define+__BAMBU_SIM__"

# verilator-sst's options: a model built from our own Verilog (ENABLE_CUSTOM_MODULE), clocked by SST on
# bambu's clock port, without verilator-sst's own tests
VERILATOR_SST_CMAKE_OPTIONS=(
  -DENABLE_CUSTOM_MODULE=ON
  -DDISABLE_TESTING=ON
  -DCLOCK_PORT_NAME=clock
)
