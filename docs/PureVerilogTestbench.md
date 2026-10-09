# Pure-Verilog testbench for verilator-sst

bambu's default testbench is a DPI-C co-simulation: the Verilog talks to a
separate C driver process. That can't run inside verilator-sst. bambu
`dev/panda` can instead generate a self-contained, DPI-free Verilog testbench
(`--testbench-style=verilog`). It is a single module whose only port is
`clock`, with the stimulus, memory model and result checks all inside it. The
`bambu-devpanda-tb` make targets of the examples run it end to end: HLS,
testbench, bambu's own Verilator run, and a run under SST through
verilator-sst.

This page ties together the pieces needed to reproduce that from scratch on
macOS/arm64. The details live in the linked READMEs, and
[BambuDevPanda.md](BambuDevPanda.md) is the full guide to the bambu side.

## Repositories

| Repository | Branch | Role |
|---|---|---|
| [tdysart/PandA-bambu](https://github.com/tdysart/PandA-bambu) | `spike/devpanda-macos-testbench` | upstream bambu `dev/panda`, built on macOS, with `--testbench-style=verilog` |
| [tdysart/soda-benchmarks](https://github.com/tdysart/soda-benchmarks) | `tjd-verilator-sst` | this repo: scripts, make targets, examples |
| [tactcomplabs/verilator-sst](https://github.com/tactcomplabs/verilator-sst) | `feature/mdpi-testbench-support` | builds the testbench into an SST component |

`--testbench-style=verilog` is not in upstream bambu, and the verilator-sst
branch carries the custom-module and link-handling support the SST run needs.

## Prerequisites

Verified on macOS 26 (arm64) with Homebrew:

* the packages listed in [BambuDevPanda.md](BambuDevPanda.md#prerequisites)
  (`llvm@19`, `cmake`, `ninja`, `boost`, `verilator`, `coreutils`, `gawk` and
  so on)
* SST-Core 16.0, built from upstream. It is not covered here; `sst` and
  `sst-config` must be in the same directory.
* Python 3
* For the MLIR/PyTorch example only: LLVM 19.1 tools, soda-opt and torch-mlir
  (see [step 4](#4-the-pytorch-example)). The C example needs none of these.

## Toolchain versions

Only the MLIR/PyTorch path needs the LLVM 19.1.5 install below. The C examples and the testbench
flow itself need only bambu and `llvm@19`.

| Tool | LLVM it uses | Needed for |
|---|---|---|
| soda-opt | built against LLVM 19.1.5 (static, no RTTI) | MLIR examples (`soda_to_llvm.mk`), sb-cli experiments, `kernel_arg_order.sh` |
| `mlir-opt`, `mlir-translate`, `opt` | the same LLVM 19.1.5 install, on `PATH` | MLIR examples (`tosa_to_linalg.sh`, `linalg_to_llvm.sh`, `llvm_to_ll.sh`, `mlir_to_graph.sh`) |
| torch-mlir | its own submodule, LLVM `d16b21b` (19 development), commit `43506726853b` | PyTorch examples; chosen so its TOSA output parses with LLVM 19.1's `mlir-opt` ([setup-torch-mlir.sh](../scripts/external/setup-torch-mlir.sh)) |
| TensorFlow MLIR tools (`tf-opt`, `tf-mlir-translate`, `flatbuffer_translate`) | their own LLVM, `acc159aea1e6` (2024-07-23, the `release/19.x` branch point), TF commit `d7f515cc2fd8` | TFLite and TensorFlow examples (`tflite_to_tosa.sh`, `graphdef_to_tosa.sh`); chosen so the TOSA output parses with LLVM 19.1's `mlir-opt` ([setup-tensorflow-mlir.sh](../scripts/external/setup-tensorflow-mlir.sh), [guide](ModelConversionTools.md)) |
| bambu `dev/panda` | Homebrew `llvm@19` (`--compiler=I386_CLANG19`) | the `bambu-devpanda-tb` targets; it reads soda-opt's LLVM 19 IR, which clang 16 cannot |
| Verilator, SST, verilator-sst | none | the SST runs |

soda-opt is what sets LLVM 19.1.5. Its README says it was tested with
llvm-project commit `ab4b5a2db582958af1ee308a790cfdb42bd24720`, which is the
`llvmorg-19.1.5` tag, and its dev container and CI build `llvmorg-19.1.5`
(`LLVM_BRANCH`). Nothing in its build checks the version, but it uses LLVM's
C++ APIs, which change between releases, so build it against exactly that
LLVM. The other LLVM 19 tools above come from the same install.

On macOS, soda-opt's `build_tools/build_llvm.sh` needs one change: it configures LLVM
with `-DLLVM_ENABLE_LLD=ON`, and lld is not installed with Homebrew's default
toolchain. [soda-opt-build-llvm-without-lld.patch](../scripts/external/soda-opt-build-llvm-without-lld.patch)
turns it off (`git apply` it in the soda-opt checkout before building). It is kept here
because soda-opt is a separate repository (`pnnl/soda-opt`).

## 1. Build bambu

Follow [BambuDevPanda.md](BambuDevPanda.md#1-build). It produces an install
tree whose `bin/bambu` is passed to the make targets as `BAMBU_DEVPANDA`.
Check the build with:

```sh
/path/to/install/bin/bambu --help | grep -A2 testbench-style
```

## 2. Get soda-benchmarks and verilator-sst

```sh
git clone -b tjd-verilator-sst git@github.com:tdysart/soda-benchmarks.git
git clone -b feature/mdpi-testbench-support git@github.com:tactcomplabs/verilator-sst.git
```

The examples below pass the verilator-sst checkout as `VERILATOR_SST_SRC`. Any
location works.

## 3. A C example

The quickest check needs no MLIR tools. From `examples/c-to-verilog/3mm`:

```sh
make output/bambu-devpanda-tb/baseline/08_sst_results.txt \
  BAMBU_DEVPANDA=/path/to/install/bin/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

This synthesizes `forward_kernel.c` for nangate45 at 5 ns and runs the
example's C testbench natively to record the memory images and the reference
results. The Verilog testbench replays them, first under bambu's own Verilator
run and then, built into a verilator-sst component, under SST. Expect
`verilator-sst: PASS in 26322 cycles`. `07_results.txt` stops after bambu's
Verilator simulation, with the same count. See the example's
[README](../examples/c-to-verilog/3mm/README.md).

## 4. The PyTorch example

[examples/pytorch-to-verilog/3mm-no_weights](../examples/pytorch-to-verilog/3mm-no_weights/README.md)
runs a PyTorch model through torch-mlir and soda-opt to LLVM IR, then through
the same flow:

```sh
make output/bambu-devpanda-tb/transformed/08_sst_results.txt \
  BAMBU_DEVPANDA=/path/to/install/bin/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

This needs soda-opt and LLVM 19.1's `mlir-opt`, `mlir-translate` and `opt` on
`PATH`, plus torch-mlir's Python package on `PYTHONPATH`.
[setup-torch-mlir.sh](../scripts/external/setup-torch-mlir.sh) builds a
torch-mlir that matches LLVM 19.1. Expect `verilator-sst: PASS in 10184 cycles`
(asap7-BC, 5 ns).

The IR has no C source to run natively, so the example's own
`forward_kernel_testbench.c` defines `forward_kernel` as the reference model
the hardware is checked against.

## 5. Dataflow designs from soda-plugins

`dev/panda` is also the only bambu that accepts the soda-plugins dataflow
designs (FIFOs between nodes); the guide is
[BambuDevPanda.md](BambuDevPanda.md#5-dataflow-designs-from-soda-plugins).

Given a bambu output directory made with
`--simulate --simulator=VERILATOR --testbench-style=verilog`,
[verilator_sst_devpanda_tb.sh](../scripts/verilator_sst_devpanda_tb.sh) builds that testbench into
a verilator-sst component and runs it under SST:

```bash
VERILATOR_SST_SRC=/path/to/verilator-sst SST=/path/to/sst \
  scripts/verilator_sst_devpanda_tb.sh <bambu_dir> results.txt
```

It expects `verilator-sst: PASS in <N> cycles`, the same count bambu reports natively, and exits
non-zero when the testbench reports a mismatch. The soda-plugins `forward` design (`gemm_small`)
passes in 1849 cycles both natively and under SST. For that flow generate the IR with
`machine-bits=64` on `sodap-dataflow-to-llvm-pipeline` and pass `--generate-interface=INFER` to
bambu; see [examples/soda-plugins](../examples/soda-plugins/README.md).

## Troubleshooting

* **The SST run reports no result.** The testbench relies on Verilator's
  `--timescale-override 1ps/1ps`, which the SST scripts pass, and needs the
  verilator-sst branch above. See also the troubleshooting list in
  [BambuDevPanda.md](BambuDevPanda.md#troubleshooting).
* **`syntax error ... Error in parsing xml ... asap7-BC.spec_data`.** The device
  files were merged by an older `etc/scripts/append_libraries.sh` that dropped
  a closing tag on macOS. Rebuild from the current `spike/devpanda-macos-testbench`,
  whose commit "append_libraries.sh: fix the merged device files on macOS" has the fix.
* **`stdio.h` not found while bambu compiles.** Export
  `SDKROOT=$(xcrun --show-sdk-path)`. The scripts do this, but a hand-run
  bambu needs it too.

## More

* The bambu branch's own notes: `MACOS_PORT.md` in `spike/devpanda-macos-testbench`.
* The scripts: [scripts/README.md](../scripts/README.md).
