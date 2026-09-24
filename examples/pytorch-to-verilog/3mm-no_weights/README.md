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
    └── bambu2023/<strategy>/   // see below
        ├── 05_kernel.c        // llvm-cbe translation of 05_llvm_<strategy>.ll
        ├── test.xml           // bambu XML test vector
        ├── 06_verilog.v
        ├── 07_results.txt     // simulated cycle count
        └── HLS_output/simulation/testbench_forward_kernel_tb.v
```


# Pure-Verilog Testbench with bambu v2023.1

Current bambu generates a DPI-C testbench. bambu v2023.1 can instead generate
a self-contained, pure-Verilog testbench from an XML test vector
(`--generate-tb=<file.xml>`). That testbench can run under verilator-sst
without a hand-written one. The `bambu2023` targets produce it.

bambu v2023.1's only front end is clang 13, which cannot read the LLVM 19 IR
soda-opt emits. So these targets first translate the IR to C with
[llvm-cbe](https://github.com/JuliaHubOSS/llvm-cbe) and synthesize that C
instead. This path uses local tools only, not the docker image:

* `bambu` v2023.1, passed as `BAMBU2023`
* `llvm-cbe` built against the same LLVM as soda-opt, passed as `LLVM_CBE`.
  Commit `21569b994b` is the last one that targets LLVM 19.1. Build it with
  [setup-llvm-cbe.sh](../../../scripts/external/setup-llvm-cbe.sh).
* torch-mlir, soda-opt, `mlir-opt`/`mlir-translate`/`opt` on `PATH` (and
  torch-mlir's python package on `PYTHONPATH`) for the earlier steps. For
  LLVM 19.1, [setup-torch-mlir.sh](../../../scripts/external/setup-torch-mlir.sh)
  builds a matching torch-mlir.

```sh
make output/bambu2023/transformed/07_results.txt \
  BAMBU2023=/path/to/panda-2023/install/bin/bambu \
  LLVM_CBE=/path/to/llvm-cbe/build/tools/llvm-cbe/llvm-cbe
```

The test vector is built from soda-opt's `forward_kernel_testbench.c`: random
inputs, and zeros for the last argument (the output). Pass
`XML_ARGS="--seed 7"` and similar to change it (see
[testbench_to_xml.py](../../../scripts/testbench_to_xml.py)). bambu checks the
simulated outputs against a host run of the same C.

The generated testbench opens `values.txt` and `results.txt` by absolute path,
so update those `$fopen` calls if you move it.
