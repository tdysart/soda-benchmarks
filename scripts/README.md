# Conversion and Lowering Scripts

This directory contains scripts that are used to convert the input,
typically a model in a high-level language, into MLIR or lower abstraction.

## Model Conversion

The following scripts are used to translate models from high-level frameworks
to TOSA MLIR.

* [tflite_to_tosa.sh](tflite_to_tosa.sh) - Converts a TFLite model `<model.tflite> to TOSA MLIR.
* [protobuf_to_tosa.sh](protobuf_to_tosa.sh) - Converts a protobuf model `<model.pb>` or `<model.pbtxt> to TOSA MLIR.
* [tf_to_tosa.sh](tf_to_tosa.sh) - Converts a TensorFlow model `<model.pb>` or `<model.pbtxt>` to TOSA MLIR.

These need `torch-mlir-opt` and the TensorFlow tools `tf-opt`, `tf-mlir-translate`
and `flatbuffer_translate` on `PATH` when docker is not used (see
[check_docker.sh](check_docker.sh)). Both are built from pinned upstream commits
whose LLVM is closest to the LLVM 19.1.5 that soda-opt uses, so their TOSA output
parses with its `mlir-opt`; the full build guide is
[docs/ModelConversionTools.md](../docs/ModelConversionTools.md):

* [external/setup-torch-mlir.sh](external/setup-torch-mlir.sh) - Builds `torch-mlir-opt` and the torch-mlir Python package.
* [external/setup-tensorflow-mlir.sh](external/setup-tensorflow-mlir.sh) - Builds the three TensorFlow tools with Bazel (about 30 minutes on 14 cores). The default location is `../tensorflow`. On macOS it works with only the Command Line Tools installed, with no full Xcode.

## Lowering

The following scripts should be used in the given order to lower the TOSA MLIR to LLVM IR.

1. [tosa_to_linalg.sh](tosa_to_linalg.sh) - Lowers TOSA MLIR to Linalg dialect.
2. [linalg_to_llvm.sh](linalg_to_llvm.sh) - Lowers Linalg dialect to LLVM dialect.
3. [llvm_to_ll.sh](llvm_to_ll.sh) - Translates MLIR with LLVM dialect to LLVM IR.

Typically, the lowering scripts will generate the following files:

* `01_tosa.mlir` - TOSA MLIR
* `02_linalg.mlir` - Linalg dialect using buffers
* `03_llvm.mlir` - LLVM dialect using buffers
* `04_llvm.ll` - LLVM IR file

## Backends

The scripts that consume the LLVM IR produced above, one per `sb-cli --backend`.
See [docs/ESPBackend.md](../docs/ESPBackend.md) for the cpu and esp ones.

* [ll_to_verilog.sh](ll_to_verilog.sh) - Synthesizes `<input.ll>` with Bambu (`--backend bambu`).
* [ll_to_verilog_verilog_tb.sh](ll_to_verilog_verilog_tb.sh) - Synthesizes `<input.ll>` with a bambu that has `--testbench-style=verilog` (branch `feature/legacy-xml-testbench` of `tdysart/PandA-bambu`) and generates its self-contained, pure-Verilog (non-DPI) testbench. [testbench_to_xml.py](testbench_to_xml.py) `--arch-xml` writes its inputs; [verilator_sst.sh](verilator_sst.sh) with [verilator_sst_tb.py](verilator_sst_tb.py) then runs the testbench under SST via verilator-sst. Wired up in [mkinc/llvm_to_verilog_verilog_tb.mk](mkinc/llvm_to_verilog_verilog_tb.mk); see [examples/pytorch-to-verilog/3mm-no_weights](../examples/pytorch-to-verilog/3mm-no_weights/README.md). The earlier bambu v2023.1 route via llvm-cbe is kept in [reference/bambu2023](reference/bambu2023/README.md).
* [c_to_verilog_devpanda_tb.sh](c_to_verilog_devpanda_tb.sh) - Synthesizes `<input.c>` with a bambu from `dev/panda` and runs the example's C testbench through the DPI-free Verilog testbench (`--testbench-style=verilog`, branch `spike/devpanda-macos-testbench` of `tdysart/PandA-bambu`). Wired up in [mkinc/c_to_verilog_devpanda_tb.mk](mkinc/c_to_verilog_devpanda_tb.mk) as the `bambu-devpanda-tb` targets; the SST run is [verilator_sst_devpanda_tb.sh](verilator_sst_devpanda_tb.sh).
* [verilator_sst_devpanda_tb.sh](verilator_sst_devpanda_tb.sh) - Runs the DPI-free testbench of a bambu `dev/panda` output directory (`--testbench-style=verilog`, see [docs/PureVerilogTestbench.md](../docs/PureVerilogTestbench.md)) under SST via verilator-sst; works for the dataflow designs of [examples/soda-plugins](../examples/soda-plugins/README.md).
* [ll_to_binary.sh](ll_to_binary.sh) - Links `<input.ll>` into a native executable (`--backend cpu`).
* [ll_to_riscv.sh](ll_to_riscv.sh) - Cross-compiles `<input.ll>` for an ESP SoC's RISC-V core and stages a baremetal application (`--backend esp`).
* [link_esp_app.sh](link_esp_app.sh) - Finishes that application's link inside an ESP checkout.
* [kernel_arg_order.sh](kernel_arg_order.sh) - Prints the order `-soda-outline-bambu-code` gave `forward_kernel`'s parameters, which is not the order `@forward` declares them in.
* [esp_gemm_demo.sh](esp_gemm_demo.sh) - Runs all three of the above configurations on PolyBench gemm.

## Using the templates

The folder [templates/make/](templates/make/) contains Makefile templates to translate the model and convert it to LLVM IR. To use the templates, copy the correct template to the root of the project and rename it to `Makefile`. Adjust the variables in the template to match your project.
Then, run `make` to translate the model and lower to LLVM IR.

Similarly, the folder [templates/bash/](templates/bash/) contains bash scripts to translate the model and convert it to LLVM IR. To use the templates, copy the correct template to the root of the project and rename it to `compile.sh`. Adjust the variables in the template to match your project.
Then, run `./compile.sh` to translate the model and lower to LLVM IR.
