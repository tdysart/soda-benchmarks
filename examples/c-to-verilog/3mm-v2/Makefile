# Compile C to LLVM

FILE_PATH=forward_kernel.c
SCRIPTS_DIR=../../../scripts
ODIR=output

# Edit to change the target
#TARGET=$(ODIR)/bambu/baseline/06_verilog.v
TARGET=$(ODIR)/bambu/baseline/07_results.txt # For simulation results

# Pure-Verilog (non-DPI) testbench, with a bambu that has
# --testbench-style=verilog. Local tools only; see
# scripts/mkinc/c_to_verilog_verilog_tb.mk.
# TARGET=$(ODIR)/bambu-verilog-tb/baseline/06_verilog.v
# TARGET=$(ODIR)/bambu-verilog-tb/baseline/07_results.txt # For simulation results
# TARGET=$(ODIR)/bambu-verilog-tb/baseline/08_sst_results.txt # Run it under SST (verilator-sst)

all: $(TARGET)

clean:
	rm -rf $(ODIR)/

# For simulation, the testbench file can be specified as a C driver, that will
# be used for both a CPU execution and for simulation.  In this example we have
# provided both examples for syntactic reference.
SIMULATION_FILE_PATH=forward_kernel_testbench.c

# Include rules to generate verilog and simulate with Bambu
#  Select the target Bambu device and clock period below, if not specified
#  default values are used.
# BAMBU_DEVICE=asap7-BC
BAMBU_DEVICE=nangate45
BAMBU_CLOCK_PERIOD=5
BAMBU_MEMPOLICY=NO_BRAM
include $(SCRIPTS_DIR)/mkinc/c_to_verilog.mk

# XML test vector for the pure-Verilog testbench (inputs only; see gen_test_xml.py).
TEST_XML=test.xml
include $(SCRIPTS_DIR)/mkinc/c_to_verilog_verilog_tb.mk
