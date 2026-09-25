# Reference: pure-Verilog testbench with bambu v2023.1

Kept for reference only. bambu 2024 built from branch
`feature/legacy-xml-testbench` of `tdysart/PandA-bambu` generates the same
testbench with `--testbench-style=verilog`, straight from soda-opt's IR (see
[llvm_to_verilog_verilog_tb.mk](../../mkinc/llvm_to_verilog_verilog_tb.mk)).
This older route was the proof of concept that showed the v2023.1 testbench
works under verilator-sst, before it was ported.

bambu v2023.1 generates a self-contained, pure-Verilog testbench from an XML
test vector (`--generate-tb=<file.xml>`). Its only front end is clang 13, which
cannot read the LLVM 19 IR that soda-opt emits: opaque pointers and
`memory(argmem: ...)` attributes. So this flow first translates the IR to C
with [llvm-cbe](https://github.com/JuliaHubOSS/llvm-cbe) and synthesizes
that C instead.

## Files

* [llvm_to_verilog_bambu2023.mk](llvm_to_verilog_bambu2023.mk): make rules
  for `$(ODIR)/bambu2023/<strategy>/{05_kernel.c,test.xml,06_verilog.v,07_results.txt,08_sst_results.txt}`.
* [ll_to_c_cbe.sh](ll_to_c_cbe.sh): LLVM IR to C with llvm-cbe. It retypes
  the kernel's `void*` arguments to `float*` (`CBE_PTR_TYPE`), since opaque
  pointers lose the element type.
* [c_to_verilog_bambu2023.sh](c_to_verilog_bambu2023.sh): bambu v2023.1
  synthesis with `--generate-tb=<test.xml>`.
* [setup-llvm-cbe.sh](setup-llvm-cbe.sh) and
  [llvm-cbe-static-llvm-link.patch](llvm-cbe-static-llvm-link.patch): build
  llvm-cbe commit `21569b994b`, the last one that targets LLVM 19.1, against
  a static, no-RTTI LLVM install. The patch links LLVM's component libraries
  instead of `libLLVM`, and the script builds with `-fno-rtti`.

The flow still uses the shared [testbench_to_xml.py](../../testbench_to_xml.py)
(with its default `_1.._N` parameter names, as llvm-cbe emits them) and
[verilator_sst.sh](../../verilator_sst.sh).

## Running it

Add this line to an example's Makefile, after the other `include` lines:

```make
include $(SCRIPTS_DIR)/reference/bambu2023/llvm_to_verilog_bambu2023.mk
```

Then, for example:

```sh
make output/bambu2023/transformed/08_sst_results.txt \
  BAMBU2023=/path/to/panda-2023/install/bin/bambu \
  LLVM_CBE=/path/to/llvm-cbe/build/tools/llvm-cbe/llvm-cbe \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

Notes:

* On macOS, bambu v2023.1 compiles its host-side testbench with Homebrew
  clang, which needs `SDKROOT`. `c_to_verilog_bambu2023.sh` sets it from
  `xcrun`.
* The expected outputs come from bambu running the same C on the host.
* The generated testbench opens `values.txt` and `results.txt` by absolute
  path, so update those `$fopen` calls if you move it.
* On the 3mm example this passed under verilator-sst in 14700 cycles. bambu
  2024's design for the same C takes 15476 cycles, since the hardware differs
  between the two bambu versions.
