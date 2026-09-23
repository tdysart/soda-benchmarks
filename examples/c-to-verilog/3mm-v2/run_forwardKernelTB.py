#
# run_forwardKernelTB.py
#
# NOTE: this targets the *modern* (current) bambu's DPI-C testbench flow
# (forward_kernel_testbench.c, built via this directory's Makefile into
# output/ and verilog_output/, then wrapped by the verilator-sst/ checkout).
# It is unrelated to the v2023.1/XML-testbench flow (test.xml, gen_test_xml.py,
# output-v2023-poc6/, output-seed7/), which runs standalone through bambu
# itself and doesn't use SST or this script at all.
#
# Minimal SST run script that exercises the "verilatorsstforwardKernelTB"
# subcomponent -- a Verilator-wrapped copy of the bambu-generated
# bambu_testbench_impl module for this example's forward_kernel.
#
# bambu_testbench_impl exposes exactly one port: "clock". The DUT, the
# memory model, and all stimulus/checking logic are instantiated inside
# it (see verilog_output/bambu_testbench.v's TestbenchFSM), and it
# self-checks its own result via bambu's generated m_fini() comparison,
# reporting PASS/FAIL to stdout ("Sim: Testbench returned: 0" == pass)
# and to results.txt (written to the current working directory). So
# "exercising" it just means toggling its clock link enough times for
# the FSM to run to completion.
#
# The subcomponent was built with ENABLE_LINK_HANDLING=ON, so its own
# internal clock handler is a no-op -- it only advances in response to
# PortEvents arriving over the "clock" SST::Link. That means a driver
# component on the other end of the link is required; this script uses
# this repo's own generic link-test component, VerilatorTestLink
# (built via -DENABLE_TESTING=ON), to send the toggle events.
#
# Usage:
#   sst run_forwardKernelTB.py -- [--cycles N] [--verbose N]
#
# Bambu reports ~12k accelerator cycles for this kernel; the default
# --cycles below is generously above that. If stdout shows
# "Sim: Simulation exceeds <N> cycles", raise --cycles.
#

import argparse
import os
import sys

import sst

# ---------------------------------------------------------------
# Point SST at the element libraries built under verilator-sst/build,
# without clobbering any SST_LIB_PATH entries the user already set.
# ---------------------------------------------------------------
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(THIS_DIR, "verilator-sst", "build")

REQUIRED_LIB_DIRS = [
    BUILD_DIR,                                                             # verilatorsstforwardKernelTB
    os.path.join(BUILD_DIR, "verilator-sst-element"),                      # verilatorcomponent
    os.path.join(BUILD_DIR, "test", "test_elements", "verilator-test-link"),  # verilatortestlink
]

existingLibPaths = [p for p in os.environ.get("SST_LIB_PATH", "").split(":") if p]
for path in REQUIRED_LIB_DIRS:
    if path not in existingLibPaths:
        existingLibPaths.append(path)
os.environ["SST_LIB_PATH"] = ":".join(existingLibPaths)

# ---------------------------------------------------------------
# CLI args (passed after "--" on the sst command line)
# ---------------------------------------------------------------
parser = argparse.ArgumentParser(description="Exercise verilatorsstforwardKernelTB over its clock link")
parser.add_argument("--cycles", type=int, default=30000,
                     help="Number of clock cycles to run (default: 30000)")
parser.add_argument("--verbose", type=int, default=1,
                     help="VerilatorTestLink verbosity level (default: 1)")
args = parser.parse_args(sys.argv[1:])

NUM_CYCLES = args.cycles

# ---------------------------------------------------------------
# Test op stream: one full clock pulse (high then low) per cycle
# ---------------------------------------------------------------
testOps = []
for i in range(NUM_CYCLES):
    testOps.append(f"clock:write:1:{i}")
    testOps.append(f"clock:write:0:{i}")

# ---------------------------------------------------------------
# VerilatorTestLink drives the "clock" link; with no model subcomponent
# of its own it registers as the (a) primary component.
# ---------------------------------------------------------------
tester = sst.Component("tester0", "verilatortestlink.VerilatorTestLink")
tester.addParams({
    "verbose": args.verbose,
    "clockFreq": "1GHz",
    "num_ports": 1,
    "portMap": ["clock:0:1:2"],   # name:id:size(bytes):direction(2=writeable)
    "testOps": testOps,
    "numCycles": NUM_CYCLES,
})

# ---------------------------------------------------------------
# VerilatorComponent hosts the verilated bambu_testbench_impl model
# ---------------------------------------------------------------
dut = sst.Component("dut0", "verilatorcomponent.VerilatorComponent")
dut.addParams({
    "numCycles": NUM_CYCLES,
})
model = dut.setSubComponent("model", "verilatorsstforwardKernelTB.VerilatorSSTforwardKernelTB")
model.addParams({
    "useVPI": False,
    "clockFreq": "1GHz",
    "clockPort": "clock",
})

# ---------------------------------------------------------------
# Wire the tester's port0 to the model's "clock" link
# ---------------------------------------------------------------
link = sst.Link("clock_link")
link.connect((tester, "port0", "0ns"), (model, "clock", "0ns"))
