# This file provides rules to generate Verilog and a pure-Verilog (non-DPI)
# testbench with bambu 2024's --testbench-style=legacy, straight from the IR.
#
# It needs a bambu built from branch feature/legacy-xml-testbench of
# tdysart/PandA-bambu (see ll_to_verilog_legacy_tb.sh). Unlike the bambu2023
# flow (llvm_to_verilog_bambu2023.mk), no llvm-cbe translation to C is needed.
# Targets, for <strategy> (baseline, optimized or transformed):
#
#   $(ODIR)/bambu-legacy/<strategy>/06_verilog.v    Verilog + testbench
#   $(ODIR)/bambu-legacy/<strategy>/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu-legacy/<strategy>/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# The test vector's expected outputs are computed by running
# 05_llvm_<strategy>.ll on the host (compiled with llc), so the testbench
# checks the hardware's results.
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU_LEGACY_TB  bambu with --testbench-style   LLC  llc for the host run
#   XML_ARGS   extra testbench_to_xml.py flags (e.g. --seed 7 --outputs 4)
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst_bambu2023.sh)
#
# Uses BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and BAMBU_MEMPOLICY like
# llvm_to_verilog.mk.

BAMBU_LEGACY_TB_SETTINGS = \
  BAMBU_LEGACY_TB=$(or $(BAMBU_LEGACY_TB),bambu) \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY)

# forward_kernel_testbench.c is written by the soda-opt step that produced
# 05_llvm_<strategy>.ll, hence the dependency on the .ll file. The same rule
# writes architecture.xml, the C types of the kernel's pointer arguments.
$(ODIR)/bambu-legacy/%/test.xml: $(ODIR)/05_llvm_%.ll $(SCRIPTS_DIR)/testbench_to_xml.py
	mkdir -p $(@D)
	LLC=$(or $(LLC),llc) \
	python3 $(SCRIPTS_DIR)/testbench_to_xml.py $(ODIR)/forward_kernel_testbench.c -o $@ \
	  --param-prefix P --param-base 0 --arch-xml $(@D)/architecture.xml --expected-from $< $(XML_ARGS)

$(ODIR)/bambu-legacy/%/06_verilog.v: $(ODIR)/05_llvm_%.ll $(ODIR)/bambu-legacy/%/test.xml
	$(BAMBU_LEGACY_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_legacy_tb.sh $^ $(@D)/architecture.xml $@

$(ODIR)/bambu-legacy/%/07_results.txt: $(ODIR)/05_llvm_%.ll $(ODIR)/bambu-legacy/%/test.xml
	BAMBU_RUN_SIMULATION=true \
	$(BAMBU_LEGACY_TB_SETTINGS) \
	$(SCRIPTS_DIR)/ll_to_verilog_legacy_tb.sh $^ $(@D)/architecture.xml $@

# The testbench is generated with the Verilog, so no bambu simulation is
# needed first; if 07_results.txt exists, its cycle count sizes the SST run.
$(ODIR)/bambu-legacy/%/08_sst_results.txt: $(ODIR)/bambu-legacy/%/06_verilog.v $(SCRIPTS_DIR)/verilator_sst_bambu2023.sh $(SCRIPTS_DIR)/verilator_sst_bambu2023_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	$(SCRIPTS_DIR)/verilator_sst_bambu2023.sh $< $@

# Keep the test vector; make would otherwise delete it as an intermediate of
# the pattern rules above.
.PRECIOUS: $(ODIR)/bambu-legacy/%/test.xml
