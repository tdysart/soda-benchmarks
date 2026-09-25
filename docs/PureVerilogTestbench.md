# Pure-Verilog testbench for verilator-sst

bambu's default testbench is a DPI-C co-simulation: the Verilog talks to a
separate C driver process. That can't run inside verilator-sst. bambu v2023.1
and earlier could instead generate a self-contained, pure-Verilog testbench
from an XML test vector. It is a single module whose only port is `clock`, with
the stimulus, memory model and result checks all inside it. That generator is
now ported to bambu 2024 as `--testbench-style=verilog`, and the
`bambu-verilog-tb` make targets run it end to end: HLS, testbench, bambu's own
Verilator run, and a run under SST through verilator-sst.

This page ties together the pieces needed to reproduce that from scratch on
macOS/arm64. The details live in the linked READMEs.

## Repositories

| Repository | Branch | Role |
|---|---|---|
| [tdysart/PandA-bambu](https://github.com/tdysart/PandA-bambu) | `feature/legacy-xml-testbench` | bambu 2024 with `--testbench-style=verilog` (the branch name predates the rename) |
| [tdysart/soda-benchmarks](https://github.com/tdysart/soda-benchmarks) | `tjd-verilator-sst` | this repo: scripts, make targets, examples |
| [tactcomplabs/verilator-sst](https://github.com/tactcomplabs/verilator-sst) | `feature/mdpi-testbench-support` | builds the testbench into an SST component |

`--testbench-style` is not in upstream bambu, and the verilator-sst branch
carries the custom-module and link-handling support the SST run needs.

## Prerequisites

Verified on macOS 26 (arm64) with Homebrew:

* `llvm@16` (bambu's front end, and `llvm-ar`/`llvm-ranlib` for its build),
  `gcc` (16), `boost`, `gmp`, `mpfr`, `cmake`, `verilator` (5.052),
  `coreutils`, and `autoconf`/`automake`/`libtool` to generate bambu's
  `configure`
* SST-Core 16.0, built from upstream. It is not covered here; `sst` and
  `sst-config` must be in the same directory.
* Python 3
* For the MLIR/PyTorch example only: LLVM 19.1 tools, soda-opt and torch-mlir
  (see [step 4](#4-the-pytorch-example)). The C examples need none of these.

## Toolchain versions

Only the MLIR/PyTorch path needs LLVM 19.1. The C examples and the testbench
flow itself need only bambu and llvm@16.

| Tool | LLVM it uses | Needed for |
|---|---|---|
| soda-opt | built against LLVM 19.1.5 (static, no RTTI) | MLIR examples (`soda_to_llvm.mk`), sb-cli experiments, `kernel_arg_order.sh` |
| `mlir-opt`, `mlir-translate`, `opt` | the same LLVM 19.1.5 install, on `PATH` | MLIR examples (`tosa_to_linalg.sh`, `linalg_to_llvm.sh`, `llvm_to_ll.sh`, `mlir_to_graph.sh`) |
| `llc` | the same LLVM 19.1.5 install | only `testbench_to_xml.py --expected-from` (optional) |
| torch-mlir | its own submodule, LLVM `d16b21b` (19 development), commit `43506726853b` | PyTorch examples; chosen so its TOSA output parses with LLVM 19.1's `mlir-opt` ([setup-torch-mlir.sh](../scripts/external/setup-torch-mlir.sh)) |
| bambu 2024 | Homebrew `llvm@16` (clang 16 front end, `llvm-ar`/`llvm-ranlib`) | all bambu targets; clang 16 reads soda-opt's LLVM 19 IR text |
| Verilator, SST, verilator-sst | none | the SST runs |
| bambu v2023.1, llvm-cbe | `llvm@14`; llvm-cbe against LLVM 19.1.5 | only the [reference flow](../scripts/reference/bambu2023/README.md) |

## 1. Build bambu

```sh
git clone -b feature/legacy-xml-testbench git@github.com:tdysart/PandA-bambu.git
cd PandA-bambu
make -f Makefile.init            # runs autoreconf to generate configure
mkdir obj && cd obj
../configure --prefix=$HOME/panda-verilog-tb/install \
  --with-clang16=/opt/homebrew/opt/llvm@16/bin/clang-16 \
  --with-gcc8=/opt/homebrew/bin/gcc-16 \
  --enable-flopoco --enable-debug --enable-opt \
  --with-boost=/opt/homebrew \
  LDFLAGS=-L/opt/homebrew/lib CFLAGS=-I/opt/homebrew/include \
  'CXXFLAGS=-I/opt/homebrew/include -D_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION' \
  CPPFLAGS=-I/opt/homebrew/include

mkdir -p /tmp/llvm-ar-shim
ln -sf /opt/homebrew/opt/llvm@16/bin/llvm-ar     /tmp/llvm-ar-shim/ar
ln -sf /opt/homebrew/opt/llvm@16/bin/llvm-ranlib /tmp/llvm-ar-shim/ranlib
PATH="/tmp/llvm-ar-shim:$PATH" make -j"$(sysctl -n hw.ncpu)" AR=llvm-ar RANLIB=llvm-ranlib
```

The `ar`/`ranlib` shim matters: Apple's tools silently empty some of bambu's
runtime archives, and HLS then fails later with confusing errors. See
`documentation/install/install_macos.doc` in that repo.

You can use the built binary in place (`obj/src/bambu`) or run `make ... install`.
Pick an install prefix that won't overwrite another bambu you rely on. Check
the build with:

```sh
obj/src/bambu --help | grep -A2 testbench-style
```

## 2. Get soda-benchmarks and verilator-sst

```sh
git clone -b tjd-verilator-sst git@github.com:tdysart/soda-benchmarks.git
cd soda-benchmarks/examples/c-to-verilog/3mm-v2
git clone -b feature/mdpi-testbench-support git@github.com:tactcomplabs/verilator-sst.git
```

The examples below pass this checkout as `VERILATOR_SST_SRC`. Any location
works.

## 3. A C example

The quickest check needs no MLIR tools. From `examples/c-to-verilog/3mm`:

```sh
make output/bambu-verilog-tb/baseline/08_sst_results.txt \
  BAMBU_VERILOG_TB=/path/to/PandA-bambu/obj/src/bambu \
  VERILATOR_SST_SRC=$PWD/../3mm-v2/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

This synthesizes `forward_kernel.c` for nangate45 at 5 ns, and generates the
testbench from an XML test vector built from `forward_kernel_testbench.c`.
bambu computes the expected outputs by running the C on the host. The make
then builds the testbench into a verilator-sst component and runs it under
SST. Expect `verilator-sst: PASS in 12122 cycles`. `07_results.txt` runs
bambu's own Verilator simulation instead, with the same count. See the
example's [README](../examples/c-to-verilog/3mm/README.md).

## 4. The PyTorch example

[examples/pytorch-to-verilog/3mm-no_weights](../examples/pytorch-to-verilog/3mm-no_weights/README.md)
runs a PyTorch model through torch-mlir and soda-opt to LLVM IR, then through
the same flow:

```sh
make output/bambu-verilog-tb/transformed/08_sst_results.txt \
  BAMBU_VERILOG_TB=/path/to/PandA-bambu/obj/src/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

This needs soda-opt and LLVM 19.1's `mlir-opt`, `mlir-translate` and `opt` on
`PATH`, plus torch-mlir's Python package on `PYTHONPATH`.
[setup-torch-mlir.sh](../scripts/external/setup-torch-mlir.sh) builds a
torch-mlir that matches LLVM 19.1. Expect `verilator-sst: PASS in 15473 cycles`
(asap7-BC, 5 ns).

LLVM IR input needs one extra file. Opaque pointers leave the kernel
arguments' element types out of the IR, so
[testbench_to_xml.py](../scripts/testbench_to_xml.py) also writes an
`architecture.xml` (`float*` and so on) that the flow passes to bambu.

## Troubleshooting

* **`results.txt` never appears under SST.** The testbench relies on
  Verilator's `--timescale-override 1ps/1ps`, which
  [verilator_sst.sh](../scripts/verilator_sst.sh) passes. It needs the
  verilator-sst branch above.
* **The default (DPI) `bambu/...` targets fail with `readlink: illegal option -- e`.**
  bambu's DPI simulation script needs GNU coreutils first on `PATH`:
  `export PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH`. The
  `bambu-verilog-tb` targets don't need it.
* **`stdio.h` not found while bambu compiles.** Export
  `SDKROOT=$(xcrun --show-sdk-path)`. The scripts do this, but a hand-run
  bambu needs it too.
* **The testbench can't open its files.** It opens
  `HLS_output/simulation/values.txt` and `results.txt` relative to bambu's
  output directory, so run it from there.

## More

* How the port works, its findings and limits: `VERILOG_TESTBENCH_PORT.md` in
  the PandA-bambu branch. Struct/array element types, C++ input and
  simulators other than Verilator aren't supported yet.
* The scripts: [scripts/README.md](../scripts/README.md).
* The earlier route, bambu v2023.1 by way of llvm-cbe, kept for reference:
  [scripts/reference/bambu2023](../scripts/reference/bambu2023/README.md).
