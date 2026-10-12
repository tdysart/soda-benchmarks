# Set model path to tflite model file

MODEL_PATH=image_classification.tflite
SCRIPTS_DIR=../../../scripts
# Make sure the output directory is not empty, many files will be generated.
# ODIR=.
ODIR=output

# Edit to change the target
# TARGET=$(ODIR)/04_llvm.ll
# TARGET=$(ODIR)/05_llvm_baseline.ll
TARGET=$(ODIR)/bambu/baseline/06_verilog.v

all: $(TARGET)

# MLIR file is generated with the torch_mlir python libraries. The file can be
# generated at the tosa dialect level. However, empirical observations show that
# generating the model at the linalg dialect level yields less instructions in
# the final LLVM IR.  
$(ODIR)/01_tosa.mlir: $(FILE_PATH)
	$(SCRIPTS_DIR)/tflite_to_tosa.sh $(MODEL_PATH) $(ODIR)/01_tosa.mlir

# Include the rules to generate linalg from a torch model translated to linalg
include $(SCRIPTS_DIR)/mkinc/tosa_to_llvm.mk
#include $(SCRIPTS_DIR)/mkinc/tflite_to_tosa

# Include the rules to generate soda LLVM IR
include $(SCRIPTS_DIR)/mkinc/soda_to_llvm.mk

# Include rules to generate verilog and simulate with Bambu
#  Select the target Bambu device and clock period below, if not specified
#  default values are used.
# BAMBU_DEVICE=asap7-BC
BAMBU_DEVICE=nangate45
BAMBU_CLOCK_PERIOD=5
include $(SCRIPTS_DIR)/mkinc/llvm_to_verilog.mk
# DPI-free testbench of bambu dev/panda, replayed under Verilator and SST. soda-opt's testbench
# has no reference model of its own, so the IR compiled natively is the reference. Local tools
# only; see scripts/mkinc/llvm_to_verilog_devpanda_tb.mk.
# TARGET=$(ODIR)/bambu-devpanda-tb/baseline/07_results.txt # Verilator
# TARGET=$(ODIR)/bambu-devpanda-tb/baseline/08_sst_results.txt # SST (verilator-sst)
# soda-opt writes the testbench while lowering the baseline, so the lowering is its recipe.
SIMULATION_FILE_PATH=$(ODIR)/forward_kernel_testbench.c
$(SIMULATION_FILE_PATH): $(ODIR)/04_llvm_baseline.mlir
include $(SCRIPTS_DIR)/mkinc/llvm_to_verilog_devpanda_tb.mk
