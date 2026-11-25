# This file provides rules to generate Verilog and simulate it with the DPI-free Verilog
# testbench of bambu dev/panda (--testbench-style=verilog), straight from soda-opt's LLVM IR. It
# is the LLVM IR counterpart of c_to_verilog_devpanda_tb.mk. Targets, for <strategy> (baseline,
# optimized or transformed):
#
#   $(ODIR)/bambu-devpanda-tb/<strategy>/06_verilog.v    Verilog
#   $(ODIR)/bambu-devpanda-tb/<strategy>/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu-devpanda-tb/<strategy>/model.json     also check against the framework and describe
#                                  the model (needs $(ODIR)/testdata.h: sb_cli's bambu-tb backend, or
#                                  scripts/tf_testdata.py for a TensorFlow model)
#   $(ODIR)/bambu-devpanda-tb/<strategy>/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# Needs a bambu built from dev/panda with --testbench-style (branch
# spike/devpanda-macos-testbench of tdysart/PandA-bambu; see ll_to_verilog_devpanda_tb.sh).
# $(SIMULATION_FILE_PATH) is the C testbench. The IR has no C source to run natively, so that file
# must also define forward_kernel: it is the reference model the hardware is compared with.
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU_DEVPANDA     the dev/panda bambu (an installed one: its settings are found from its path)
#   BAMBU_COMPILER     bambu --compiler (default I386_CLANG19)    CLANG_BIN  directory of that clang (default: clang-19 on PATH)
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst_devpanda_tb.sh)
#
# Uses SIMULATION_FILE_PATH, BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and BAMBU_MEMPOLICY like
# llvm_to_verilog.mk.

LL_DEVPANDA_TB_SETTINGS = \
  BAMBU_DEVPANDA=$(or $(BAMBU_DEVPANDA),bambu) \
  BAMBU_COMPILER=$(or $(BAMBU_COMPILER),I386_CLANG19) \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY) \
  $(if $(CLANG_BIN),CLANG_BIN=$(CLANG_BIN))

$(ODIR)/bambu-devpanda-tb/%/06_verilog.v: $(ODIR)/05_llvm_%.ll $(SIMULATION_FILE_PATH)
	mkdir -p $(@D)
	$(LL_DEVPANDA_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_devpanda_tb.sh $^ $@

$(ODIR)/bambu-devpanda-tb/%/07_results.txt: $(ODIR)/05_llvm_%.ll $(SIMULATION_FILE_PATH)
	mkdir -p $(@D)
	BAMBU_RUN_SIMULATION=true \
	$(LL_DEVPANDA_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_devpanda_tb.sh $^ $(@D)/06_verilog.v
	test -s $@

# The SST run reuses the testbench, the memory images and bambu's own cycle count from the
# simulation, so that has to have run first.
$(ODIR)/bambu-devpanda-tb/%/08_sst_results.txt: $(ODIR)/bambu-devpanda-tb/%/07_results.txt $(SCRIPTS_DIR)/verilator_sst_devpanda_tb.sh $(SCRIPTS_DIR)/verilator_sst_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	TOP_FNAME=forward_kernel \
	$(SCRIPTS_DIR)/verilator_sst_devpanda_tb.sh $(@D) $@

# bambu's testbench on the kernel's real inputs, for an experiment with test data (sb_cli's
# bambu-tb backend sets SIMULATION_FILE_PATH to it). soda-opt's own testbench sets every input
# to 1.0, which hides swapped arguments and similar errors; see scripts/gen_bambu_tb.py.
$(ODIR)/bambu_testbench.c: $(ODIR)/testdata.h $(SCRIPTS_DIR)/gen_bambu_tb.py $(SCRIPTS_DIR)/testdata.py
	python3 $(SCRIPTS_DIR)/gen_bambu_tb.py $< $@

# The model directory: model.json beside bambu's output, with the check of the results against
# the framework's (scripts/write_model_json.py; the format is soda-sst-system's docs/ModelFormat.md).
# It is written even when that check fails, so the verdict can be read, and the rule then fails.
$(ODIR)/bambu-devpanda-tb/%/model.json: $(ODIR)/bambu-devpanda-tb/%/07_results.txt $(ODIR)/testdata.h \
    $(SCRIPTS_DIR)/write_model_json.py $(SCRIPTS_DIR)/check_golden.py $(SCRIPTS_DIR)/testdata.py
	python3 $(SCRIPTS_DIR)/write_model_json.py $(@D) $(ODIR)/testdata.h

# Keep the simulation result; make would otherwise delete it as an intermediate of the SST rule.
.PRECIOUS: $(ODIR)/bambu-devpanda-tb/%/07_results.txt
