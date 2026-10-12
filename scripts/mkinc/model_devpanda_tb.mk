# Everything a model Makefile needs, after its tosa_to_llvm.mk include, to lower the model with
# soda-opt and run it through the DPI-free Verilog testbench of bambu dev/panda (see
# llvm_to_verilog_devpanda_tb.mk). Targets, with <strategy> baseline or optimized:
#
#   $(ODIR)/bambu-devpanda-tb/<strategy>/06_verilog.v      Verilog
#   $(ODIR)/bambu-devpanda-tb/<strategy>/07_results.txt    also simulate with Verilator
#   $(ODIR)/bambu-devpanda-tb/<strategy>/08_sst_results.txt   run under SST (verilator-sst)
#
# soda-opt's testbench has no reference model, so the IR compiled natively is the reference. The
# device settings can be overridden on the make command line.

# (a Makefile that already included it keeps its own copy)
ifeq ($(filter %/soda_to_llvm.mk,$(MAKEFILE_LIST)),)
include $(SCRIPTS_DIR)/mkinc/soda_to_llvm.mk
endif

BAMBU_DEVICE ?= nangate45
BAMBU_CLOCK_PERIOD ?= 5
BAMBU_MEMPOLICY ?= NO_BRAM

# soda-opt writes the testbench while lowering the baseline, so the lowering is its recipe.
SIMULATION_FILE_PATH=$(ODIR)/forward_kernel_testbench.c
$(SIMULATION_FILE_PATH): $(ODIR)/04_llvm_baseline.mlir

include $(SCRIPTS_DIR)/mkinc/llvm_to_verilog_devpanda_tb.mk
