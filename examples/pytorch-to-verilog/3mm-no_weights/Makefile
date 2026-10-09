# Compile Torch model to LLVM

FILE_PATH=torchscript.py
TRANSFORM_PATH=transform.mlir
SCRIPTS_DIR=../../../scripts
# Make sure the output directory is not empty, many files will be generated.
# ODIR=.
ODIR=output

# Edit to change the target
# TARGET=$(ODIR)/04_llvm.ll

# TARGET=$(ODIR)/bambu/baseline/06_verilog.v
# TARGET=$(ODIR)/bambu/baseline/07_results.txt # For simulation results

# TARGET=$(ODIR)/bambu/optimized/06_verilog.v
# TARGET=$(ODIR)/bambu/optimized/07_results.txt # For simulation results

TARGET=$(ODIR)/bambu/transformed/06_verilog.v
# TARGET=$(ODIR)/bambu/transformed/07_results.txt # For simulation results

# DPI-free testbench of bambu dev/panda, run from the C testbench below. Local tools only; see
# scripts/mkinc/llvm_to_verilog_devpanda_tb.mk.
# TARGET=$(ODIR)/bambu-devpanda-tb/transformed/06_verilog.v
# TARGET=$(ODIR)/bambu-devpanda-tb/transformed/07_results.txt # For simulation results
# TARGET=$(ODIR)/bambu-devpanda-tb/transformed/08_sst_results.txt # Run it under SST (verilator-sst)

all: $(TARGET)

# Generate MLIR from Torch model
$(ODIR)/01_tosa.mlir: $(FILE_PATH) 
	python $(FILE_PATH) $@ --dialect=tosa

# Put the transform schedule on the output directory where it is expected
$(ODIR)/04_transform_sched.mlir: $(TRANSFORM_PATH) 
	cp $< $@ 

# Include the rules to generate linalg from a torch model translated to linalg
include $(SCRIPTS_DIR)/mkinc/tosa_to_llvm.mk

# Include the rules to generate soda LLVM IR
include $(SCRIPTS_DIR)/mkinc/soda_to_llvm.mk

# Include rules to generate verilog and simulate with Bambu
#  Select the target Bambu device and clock period below, if not specified
#  default values are used.
BAMBU_DEVICE=asap7-BC
# BAMBU_DEVICE=nangate45
BAMBU_CLOCK_PERIOD=5
include $(SCRIPTS_DIR)/mkinc/llvm_to_verilog.mk

# The testbench of the dev/panda flow: a C driver that also defines forward_kernel, the reference
# model of the generated hardware (soda-opt's own testbench has none, so it is not used here).
SIMULATION_FILE_PATH=forward_kernel_testbench.c
include $(SCRIPTS_DIR)/mkinc/llvm_to_verilog_devpanda_tb.mk
