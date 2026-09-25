#
# verilator_sst_tb.py
#
# SST configuration that runs bambu's self-contained, pure-Verilog (non-DPI)
# testbench under verilator-sst. Used by verilator_sst.sh.
#
# bambu's --generate-tb=<file.xml> testbench (testbench_<kernel>_tb.v) is a
# top module whose only port is `clock`. All stimulus, memory and result
# checking live inside it, so this only toggles the clock through a
# VerilatorTestLink. The testbench writes its pass/fail and cycle count to the
# results.txt path baked into it when bambu generated it.
#
# Adapted from examples/c-to-verilog/3mm-v2/run_forwardKernelTB_v2023.py.
#
# Usage:
#   sst verilator_sst_tb.py -- --build-dir <verilator-sst build> [--device forwardKernelTB] [--cycles N]
#
# Under Verilator, the testbench's $finish only sets a flag, so every clock
# edge after it completes prints another $finish notice. Keep --cycles close
# to bambu's reported cycle count.
#

import argparse
import os
import sys

import sst

parser = argparse.ArgumentParser(description="Run a bambu self-contained Verilog testbench over its clock link")
parser.add_argument("--build-dir", required=True, help="verilator-sst build directory (ENABLE_CUSTOM_MODULE=ON)")
parser.add_argument("--device", default="forwardKernelTB", help="VERILOG_DEVICE the build was configured with")
parser.add_argument("--cycles", type=int, default=40000, help="Number of clock cycles to run (default: 40000)")
parser.add_argument("--verbose", type=int, default=1, help="Verbosity level (default: 1)")
args = parser.parse_args(sys.argv[1:])

BUILD_DIR = os.path.abspath(args.build_dir)
NUM_CYCLES = args.cycles

# Point SST at the element libraries in the build, keeping any SST_LIB_PATH
# entries the user already set.
REQUIRED_LIB_DIRS = [
    BUILD_DIR,                                                                  # verilatorsst<device>
    os.path.join(BUILD_DIR, "verilator-sst-element"),                           # verilatorcomponent
    os.path.join(BUILD_DIR, "test", "test_elements", "verilator-test-link"),    # verilatortestlink
]
libPaths = [p for p in os.environ.get("SST_LIB_PATH", "").split(":") if p]
for path in REQUIRED_LIB_DIRS:
    if path not in libPaths:
        libPaths.append(path)
os.environ["SST_LIB_PATH"] = ":".join(libPaths)

# One full clock pulse (high then low) per cycle.
testOps = []
for i in range(NUM_CYCLES):
    testOps.append(f"clock:write:1:{i}")
    testOps.append(f"clock:write:0:{i}")

# VerilatorTestLink drives the "clock" link.
tester = sst.Component("tester0", "verilatortestlink.VerilatorTestLink")
tester.addParams({
    "verbose": args.verbose,
    "clockFreq": "1GHz",
    "num_ports": 1,
    "portMap": ["clock:0:1:2"],   # name:id:size(bytes):direction(2=writeable)
    "testOps": testOps,
    "numCycles": NUM_CYCLES,
})

# VerilatorComponent hosts the verilated testbench.
dut = sst.Component("dut0", "verilatorcomponent.VerilatorComponent")
dut.addParams({
    "numCycles": NUM_CYCLES,
    "verbose": args.verbose,
})
model = dut.setSubComponent("model", f"verilatorsst{args.device}.VerilatorSST{args.device}")
model.addParams({
    "useVPI": False,
    "clockFreq": "1GHz",
    "clockPort": "clock",
    "verbose": args.verbose,
})

link = sst.Link("clock_link")
link.connect((tester, "port0", "0ns"), (model, "clock", "0ns"))
