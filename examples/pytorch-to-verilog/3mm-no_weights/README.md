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
    └── bambu-devpanda-tb/<strategy>/  // see below
        ├── 06_verilog.v
        ├── 07_results.txt     // simulated cycle count
        ├── tb_init.mem, tb_expected.mem // memory images recorded from the C testbench
        ├── HLS_output/simulation/bambu_testbench.v
        ├── 08_sst_results.txt // same, from the run under SST
        └── verilator-sst/     // staged Verilog, verilator-sst build, sst-run.log
```


# Pure-Verilog Testbench

bambu's default testbench uses DPI-C. With `--testbench-style=verilog`, bambu
instead generates a self-contained, DPI-free Verilog testbench that can run
under verilator-sst. The `bambu-devpanda-tb` targets produce it.

`--testbench-style` is not in upstream bambu yet: it comes from branch
`spike/devpanda-macos-testbench` of `tdysart/PandA-bambu`, which is upstream's
`dev/panda` built on macOS ([guide](../../../docs/BambuDevPanda.md)). This path
uses local tools only, not the docker image:

* bambu built from that branch, passed as `BAMBU_DEVPANDA`
* torch-mlir, soda-opt, `mlir-opt`/`mlir-translate`/`opt` on `PATH` (and
  torch-mlir's python package on `PYTHONPATH`) for the earlier steps. For
  LLVM 19.1, [setup-torch-mlir.sh](../../../scripts/external/setup-torch-mlir.sh)
  builds a matching torch-mlir.

```sh
make output/bambu-devpanda-tb/transformed/07_results.txt \
  BAMBU_DEVPANDA=/path/to/install-devpanda19/bin/bambu
```

[forward_kernel_testbench.c](forward_kernel_testbench.c) is the C testbench.
bambu runs it natively to record the memory images and the reference results,
and the Verilog testbench replays them. The IR has no C source to run, so this
file also defines `forward_kernel` (three chained matrix products, in single
precision) as the reference model the hardware is compared with. The inputs
are small multiples of 0.25 or 0.5, so the sums are exact whatever order the
tiled kernel adds them in, and the check is bit for bit. The shapes in it
(`M`, `K`, `L`, `P`, `N`) must match those in `torchscript.py`. soda-opt's own
generated `output/forward_kernel_testbench.c` has no reference model, so it is
not used.

The target device is `nangate45` (`BAMBU_DEVPANDA_DEVICE` in the Makefile): the
asap7 device files do not load in the `dev/panda` bambu yet. Expect 23160
cycles.


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
make output/bambu-devpanda-tb/transformed/08_sst_results.txt \
  BAMBU_DEVPANDA=/path/to/install-devpanda19/bin/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

The run fails if the testbench reports a mismatch or doesn't finish.
By default it runs bambu's simulated cycle count plus 10%; set `SST_CYCLES` to
override. The SST configuration is
[verilator_sst_tb.py](../../../scripts/verilator_sst_tb.py), driven by
[verilator_sst_devpanda_tb.sh](../../../scripts/verilator_sst_devpanda_tb.sh).
