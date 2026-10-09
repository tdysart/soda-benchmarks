#!/bin/bash
# Synthesize soda-opt's LLVM IR with bambu dev/panda and run a C testbench through the DPI-free
# Verilog testbench of --testbench-style=verilog.
#
# Usage: ll_to_verilog_devpanda_tb.sh <input.ll> <testbench.c> <output.v>
#
# This is c_to_verilog_devpanda_tb.sh, which takes either kind of input; see it for the outputs
# and the environment variables. The IR has no C source to run natively, so <testbench.c> has to
# define the top function (forward_kernel) as the reference model that the hardware's results
# are compared with, next to the main that calls it.

exec "$(dirname "${BASH_SOURCE[0]}")/c_to_verilog_devpanda_tb.sh" "$@"
