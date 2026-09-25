# This file provides rules to generate Verilog and a pure-Verilog (non-DPI)
# testbench from C with bambu's --testbench-style=verilog. It is the C-input
# counterpart of llvm_to_verilog_verilog_tb.mk and needs the same bambu, built
# from branch feature/legacy-xml-testbench of tdysart/PandA-bambu (see
# c_to_verilog_verilog_tb.sh). Targets:
#
#   $(ODIR)/bambu-verilog-tb/baseline/06_verilog.v    Verilog + testbench
#   $(ODIR)/bambu-verilog-tb/baseline/07_results.txt  also simulate with Verilator
#   $(ODIR)/bambu-verilog-tb/baseline/08_sst_results.txt
#                                  run the testbench under SST via verilator-sst
#
# The test vector holds inputs only; bambu computes the expected outputs by
# running $(FILE_PATH) on the host. By default it is generated from
# $(SIMULATION_FILE_PATH) with random inputs; set TEST_XML to use an XML test
# vector of your own instead.
#
# Local tools only (no docker). Override on the command line or environment:
#   BAMBU_VERILOG_TB  bambu with --testbench-style
#   TEST_XML   XML test vector to use instead of a generated one
#   XML_ARGS   extra testbench_to_xml.py flags (e.g. --seed 7)
#   VERILATOR_SST_SRC  verilator-sst checkout     SST  sst binary
#   SST_CYCLES         clock cycles for the SST run (see verilator_sst.sh)
#
# Uses FILE_PATH, SIMULATION_FILE_PATH, BAMBU_DEVICE, BAMBU_CLOCK_PERIOD and
# BAMBU_MEMPOLICY like c_to_verilog.mk.

C_VERILOG_TB_SETTINGS = \
  BAMBU_VERILOG_TB=$(or $(BAMBU_VERILOG_TB),bambu) \
  BAMBU_DEVICE=$(BAMBU_DEVICE) \
  BAMBU_CLOCK_PERIOD=$(BAMBU_CLOCK_PERIOD) \
  BAMBU_MEMPOLICY=$(BAMBU_MEMPOLICY)

ifdef TEST_XML
$(ODIR)/bambu-verilog-tb/baseline/test.xml: $(TEST_XML)
	mkdir -p $(@D)
	cp $< $@
else
# The XML keys are the parameter names bambu sees (P0..PN in these examples).
$(ODIR)/bambu-verilog-tb/baseline/test.xml: $(SIMULATION_FILE_PATH) $(SCRIPTS_DIR)/testbench_to_xml.py
	mkdir -p $(@D)
	python3 $(SCRIPTS_DIR)/testbench_to_xml.py $< -o $@ --param-prefix P --param-base 0 $(XML_ARGS)
endif

$(ODIR)/bambu-verilog-tb/baseline/06_verilog.v: $(FILE_PATH) $(ODIR)/bambu-verilog-tb/baseline/test.xml
	$(C_VERILOG_TB_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_verilog_tb.sh $^ $@

$(ODIR)/bambu-verilog-tb/baseline/07_results.txt: $(FILE_PATH) $(ODIR)/bambu-verilog-tb/baseline/test.xml
	BAMBU_RUN_SIMULATION=true \
	$(C_VERILOG_TB_SETTINGS) \
	$(SCRIPTS_DIR)/c_to_verilog_verilog_tb.sh $^ $@

# The testbench is generated with the Verilog, so no bambu simulation is
# needed first; if 07_results.txt exists, its cycle count sizes the SST run.
$(ODIR)/bambu-verilog-tb/baseline/08_sst_results.txt: $(ODIR)/bambu-verilog-tb/baseline/06_verilog.v $(SCRIPTS_DIR)/verilator_sst.sh $(SCRIPTS_DIR)/verilator_sst_tb.py
	VERILATOR_SST_SRC=$(VERILATOR_SST_SRC) \
	SST=$(or $(SST),sst) \
	SST_CYCLES=$(SST_CYCLES) \
	$(SCRIPTS_DIR)/verilator_sst.sh $< $@
