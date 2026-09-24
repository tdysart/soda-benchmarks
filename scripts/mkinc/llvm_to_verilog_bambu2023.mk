# This file provides rules to generate Verilog and a pure-Verilog (non-DPI)
# testbench with bambu v2023.1, by way of C.
#
# bambu v2023.1's front end (clang 13) cannot read soda-opt's LLVM 19 IR, so
# the IR of a strategy (baseline, optimized or transformed) is first
# translated to C with llvm-cbe. Targets, for <strategy>:
#
#   $(ODIR)/bambu2023/<strategy>/06_verilog.v    Verilog + testbench
#   $(ODIR)/bambu2023/<strategy>/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu2023/<strategy>/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU2023  bambu v2023.1 binary     LLVM_CBE  llvm-cbe binary
#   XML_ARGS   extra testbench_to_xml.py flags (e.g. --seed 7 --outputs 4)
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst_bambu2023.sh)
#
# Uses BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and BAMBU_MEMPOLICY like
# llvm_to_verilog.mk.

BAMBU2023_SETTINGS = \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY)

$(ODIR)/bambu2023/%/05_kernel.c: $(ODIR)/05_llvm_%.ll $(SCRIPTS_DIR)/ll_to_c_cbe.sh
	$(SCRIPTS_DIR)/ll_to_c_cbe.sh $< $@

# forward_kernel_testbench.c is written by the soda-opt step that produced
# 05_llvm_<strategy>.ll, hence the dependency on the .ll file.
$(ODIR)/bambu2023/%/test.xml: $(ODIR)/05_llvm_%.ll $(SCRIPTS_DIR)/testbench_to_xml.py
	python3 $(SCRIPTS_DIR)/testbench_to_xml.py $(ODIR)/forward_kernel_testbench.c -o $@ $(XML_ARGS)

$(ODIR)/bambu2023/%/06_verilog.v: $(ODIR)/bambu2023/%/05_kernel.c $(ODIR)/bambu2023/%/test.xml
	$(BAMBU2023_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_bambu2023.sh $^ $@

$(ODIR)/bambu2023/%/07_results.txt: $(ODIR)/bambu2023/%/05_kernel.c $(ODIR)/bambu2023/%/test.xml
	BAMBU_RUN_SIMULATION=true \
	$(BAMBU2023_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_bambu2023.sh $^ $@

# The testbench is generated with the Verilog, so no bambu simulation is
# needed first; if 07_results.txt exists, its cycle count sizes the SST run.
$(ODIR)/bambu2023/%/08_sst_results.txt: $(ODIR)/bambu2023/%/06_verilog.v $(SCRIPTS_DIR)/verilator_sst_bambu2023.sh $(SCRIPTS_DIR)/verilator_sst_bambu2023_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	$(SCRIPTS_DIR)/verilator_sst_bambu2023.sh $< $@

# Keep the C translation and test vector; make would otherwise delete them as
# intermediates of the pattern rules above.
.PRECIOUS: $(ODIR)/bambu2023/%/05_kernel.c $(ODIR)/bambu2023/%/test.xml
