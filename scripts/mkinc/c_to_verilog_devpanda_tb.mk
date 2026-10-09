# This file provides rules to generate Verilog and simulate it with the DPI-free Verilog
# testbench of bambu dev/panda (--testbench-style=verilog), from C. It uses the example's C
# testbench ($(SIMULATION_FILE_PATH)), run natively to record the memory images and the
# reference results. Targets:
#
#   $(ODIR)/bambu-devpanda-tb/baseline/06_verilog.v    Verilog
#   $(ODIR)/bambu-devpanda-tb/baseline/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu-devpanda-tb/baseline/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# Needs a bambu built from dev/panda with --testbench-style (branch
# spike/devpanda-macos-testbench of tdysart/PandA-bambu; see c_to_verilog_devpanda_tb.sh), and the
# kernel's interfaces declared with the dev/panda pragma syntax:
#   #pragma HLS interface port=P0 mode=m_axi offset=direct bundle=gmem0
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU_DEVPANDA     the dev/panda bambu (an installed one: its settings are found from its path)
#   BAMBU_COMPILER     bambu --compiler (default I386_CLANG19)    CLANG_BIN  directory of that clang
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst_devpanda_tb.sh)
#
# Uses FILE_PATH, SIMULATION_FILE_PATH, BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and BAMBU_MEMPOLICY like
# c_to_verilog.mk.

C_DEVPANDA_TB_SETTINGS = \
  BAMBU_DEVPANDA=$(or $(BAMBU_DEVPANDA),bambu) \
  BAMBU_COMPILER=$(or $(BAMBU_COMPILER),I386_CLANG19) \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY) \
  $(if $(CLANG_BIN),CLANG_BIN=$(CLANG_BIN))

$(ODIR)/bambu-devpanda-tb/baseline/06_verilog.v: $(FILE_PATH) $(SIMULATION_FILE_PATH)
	mkdir -p $(@D)
	$(C_DEVPANDA_TB_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_devpanda_tb.sh $^ $@

$(ODIR)/bambu-devpanda-tb/baseline/07_results.txt: $(FILE_PATH) $(SIMULATION_FILE_PATH)
	mkdir -p $(@D)
	BAMBU_RUN_SIMULATION=true \
	$(C_DEVPANDA_TB_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_devpanda_tb.sh $^ $(@D)/06_verilog.v
	test -s $@

# The SST run reuses the testbench, the memory images and bambu's own cycle count from the
# simulation, so that has to have run first.
$(ODIR)/bambu-devpanda-tb/baseline/08_sst_results.txt: $(ODIR)/bambu-devpanda-tb/baseline/07_results.txt $(SCRIPTS_DIR)/verilator_sst_devpanda_tb.sh $(SCRIPTS_DIR)/verilator_sst_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	TOP_FNAME=forward_kernel \
	$(SCRIPTS_DIR)/verilator_sst_devpanda_tb.sh $(@D) $@
