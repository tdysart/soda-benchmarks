# This file provides rules to generate Verilog and a pure-Verilog (non-DPI)
# testbench with bambu 2024's --testbench-style=verilog, straight from the IR.
#
# It needs a bambu built from branch feature/legacy-xml-testbench of
# tdysart/PandA-bambu (see ll_to_verilog_verilog_tb.sh). Unlike the old bambu2023
# flow (scripts/reference/bambu2023), no llvm-cbe translation to C is needed.
# Targets, for <strategy> (baseline, optimized or transformed):
#
#   $(ODIR)/bambu-verilog-tb/<strategy>/06_verilog.v    Verilog + testbench
#   $(ODIR)/bambu-verilog-tb/<strategy>/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu-verilog-tb/<strategy>/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# The test vector holds inputs only: bambu computes the expected outputs by
# running 05_llvm_<strategy>.ll on the host, and the testbench checks the
# hardware's results against them.
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU_VERILOG_TB  bambu with --testbench-style
#   XML_ARGS   extra testbench_to_xml.py flags (e.g. --seed 7 --outputs 4)
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst.sh)
#
# Uses BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and BAMBU_MEMPOLICY like
# llvm_to_verilog.mk.

BAMBU_VERILOG_TB_SETTINGS = \
  BAMBU_VERILOG_TB=$(or $(BAMBU_VERILOG_TB),bambu) \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY)

# forward_kernel_testbench.c is written by the soda-opt step that produced
# 05_llvm_<strategy>.ll, hence the dependency on the .ll file. The same rule
# writes architecture.xml, the C types of the kernel's pointer arguments.
$(ODIR)/bambu-verilog-tb/%/test.xml: $(ODIR)/05_llvm_%.ll $(SCRIPTS_DIR)/testbench_to_xml.py
	mkdir -p $(@D)
	python3 $(SCRIPTS_DIR)/testbench_to_xml.py $(ODIR)/forward_kernel_testbench.c -o $@ \
	  --param-prefix P --param-base 0 --arch-xml $(@D)/architecture.xml $(XML_ARGS)

$(ODIR)/bambu-verilog-tb/%/06_verilog.v: $(ODIR)/05_llvm_%.ll $(ODIR)/bambu-verilog-tb/%/test.xml
	$(BAMBU_VERILOG_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_verilog_tb.sh $^ $(@D)/architecture.xml $@

$(ODIR)/bambu-verilog-tb/%/07_results.txt: $(ODIR)/05_llvm_%.ll $(ODIR)/bambu-verilog-tb/%/test.xml
	BAMBU_RUN_SIMULATION=true \
	$(BAMBU_VERILOG_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_verilog_tb.sh $^ $(@D)/architecture.xml $@

# The testbench is generated with the Verilog, so no bambu simulation is
# needed first; if 07_results.txt exists, its cycle count sizes the SST run.
$(ODIR)/bambu-verilog-tb/%/08_sst_results.txt: $(ODIR)/bambu-verilog-tb/%/06_verilog.v $(SCRIPTS_DIR)/verilator_sst.sh $(SCRIPTS_DIR)/verilator_sst_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	$(SCRIPTS_DIR)/verilator_sst.sh $< $@

# Keep the test vector; make would otherwise delete it as an intermediate of
# the pattern rules above.
.PRECIOUS: $(ODIR)/bambu-verilog-tb/%/test.xml
