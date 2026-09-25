# PyTorch to Verilog Generation Example

In this example, we will show how to lower a simple PyTorch model to Verilog
using scripts and binaries from the MLIR Tools used by SODA 
[docker image](https://hub.docker.com/r/agostini01/soda).


# Instructions for Docker Users

1. Install Docker, VS Code, and the VS Code [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-containers).
2. Open the `soda-benchmarks` project in a VS Code development container. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS) and select: `Dev Containers: Reopen in Container`. This will download the Docker image and start the container.
3. Once inside the container, navigate to this folder and run `make` to compile the example.


## Selecting an Optimization Strategy

Change the `TARGET=` variable in the [`Makefile`](Makefile) to select the desired optimization strategy.


## Artifacts

The `<strategy>` can be either `baseline` or `optimized`, and is determined by the optimization pipeline in `soda-opt`.

```
└── output
    ├── 01_tosa.mlir
    ├── 02_linalg_on_tensors.mlir
    ├── 02_linalg.mlir        // with buffers
    ├── 04_llvm_<strategy>.mlir
    ├── 05_llvm_<strategy>.ll // LLVM IR file
    ├── bambu/<strategy>/06_verilog.v
    └── bambu-verilog-tb/<strategy>/  // see below
        ├── test.xml           // bambu XML test vector (inputs)
        ├── architecture.xml   // C types of the kernel arguments
        ├── 06_verilog.v
        ├── 07_results.txt     // simulated cycle count
        ├── HLS_output/simulation/testbench_forward_kernel_tb.v
        ├── 08_sst_results.txt // same, from the run under SST
        └── verilator-sst/     // staged Verilog, verilator-sst build, sst-run.log
```


# Pure-Verilog Testbench

bambu's default testbench uses DPI-C. With `--testbench-style=verilog`, bambu
instead generates a self-contained, pure-Verilog testbench from an XML test
vector (`--generate-tb=<file.xml>`), the one bambu v2023.1 and earlier
generated. It can run under verilator-sst without a hand-written testbench.
The `bambu-verilog-tb` targets produce it.

`--testbench-style` is not in upstream bambu yet: it comes from branch
`feature/legacy-xml-testbench` of `tdysart/PandA-bambu`. This path uses local
tools only, not the docker image:

* bambu built from that branch, passed as `BAMBU_VERILOG_TB`
* torch-mlir, soda-opt, `mlir-opt`/`mlir-translate`/`opt` on `PATH` (and
  torch-mlir's python package on `PYTHONPATH`) for the earlier steps. For
  LLVM 19.1, [setup-torch-mlir.sh](../../../scripts/external/setup-torch-mlir.sh)
  builds a matching torch-mlir.

```sh
make output/bambu-verilog-tb/transformed/07_results.txt \
  BAMBU_VERILOG_TB=/path/to/PandA-bambu/obj/src/bambu
```

[testbench_to_xml.py](../../../scripts/testbench_to_xml.py) builds `test.xml`
from soda-opt's `forward_kernel_testbench.c`: random inputs, and zeros for the
last argument (the output). Pass `XML_ARGS="--seed 7"` and similar to change
it. The XML holds inputs only; bambu runs `05_llvm_<strategy>.ll` on the host
to get the expected outputs. The script also writes `architecture.xml`, passed
to bambu as `--architecture-xml`, because opaque pointers leave the
arguments' element types (`float*`) out of the IR.
(`testbench_to_xml.py --expected-from` can still put host-computed outputs
into the XML, e.g. to cross-check bambu.)

The testbench opens `HLS_output/simulation/values.txt` and `results.txt`
relative to the output directory, so run it from there.


## Running the testbench under SST

The testbench's top module has a single port, `clock`, so verilator-sst can
drive it directly. `08_sst_results.txt` builds it into a verilator-sst
component and runs it under SST. It needs:

* a verilator-sst checkout with custom-module and link-handling support
  (branch `feature/mdpi-testbench-support` of
  `tactcomplabs/verilator-sst`), passed as `VERILATOR_SST_SRC`
* the `sst` binary, passed as `SST`. `sst-config` must be in the same
  directory.

```sh
make output/bambu-verilog-tb/transformed/08_sst_results.txt \
  BAMBU_VERILOG_TB=/path/to/PandA-bambu/obj/src/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

The run fails if the testbench reports a mismatch or doesn't finish.
By default it runs bambu's simulated cycle count plus 10% (from
`07_results.txt` if you built it), or 40000 cycles; set `SST_CYCLES` to
override. The SST configuration is
[verilator_sst_tb.py](../../../scripts/verilator_sst_tb.py).

The earlier route to the same testbench, bambu v2023.1 by way of llvm-cbe, is
kept for reference in [scripts/reference/bambu2023](../../../scripts/reference/bambu2023/README.md).
