# C to Verilog Example

Bambu HLS can convert C code to Verilog. This example demonstrates that flow with the 3mm benchmark. The Makefile is configured to generate Verilog and run a simulation to verify the results.

**This flow bypasses the MLIR passes and LLVM IR optimizations**. As a result, the generated Verilog is influenced only by the C implementation and the pragmas used in the code.


## What is needed?

The kernel code is in `forward_kernel.c`. The testbench code is in `forward_kernel_testbench.c`. The Makefile is configured to use these files to generate the Verilog and run the simulation.


## How to run?

```
make
```

Which by default will generate the verilog file.
To run the simulation, you can edit the `Makefile` to specify the target as the results file, which will trigger the simulation step:

```bash
# TARGET=$(ODIR)/bambu/baseline/06_verilog.v
TARGET=$(ODIR)/bambu/baseline/07_results.txt
```

Then run `make` again to execute the simulation which will verify the final verilog memory state against the memory state of a CPU execution of the C code. This will aslo provide a report on the number of cycles taken to execute the generated kernel.

## Pure-Verilog testbench

bambu's default testbench uses DPI-C. The `bambu-verilog-tb` targets instead
generate a self-contained, pure-Verilog testbench (`--testbench-style=verilog`)
that can run under verilator-sst. They use local tools, not the docker image:
a bambu built from branch `feature/legacy-xml-testbench` of
`tdysart/PandA-bambu`, passed as `BAMBU_VERILOG_TB`, and for the SST run a
verilator-sst checkout (`VERILATOR_SST_SRC`) and the `sst` binary (`SST`).

```sh
make output/bambu-verilog-tb/baseline/08_sst_results.txt \
  BAMBU_VERILOG_TB=/path/to/PandA-bambu/obj/src/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

`07_results.txt` runs bambu's own Verilator simulation instead. The XML test vector
is generated from `forward_kernel_testbench.c` with random inputs; pass
`XML_ARGS="--seed 7"` and similar to change it, or `TEST_XML=<file>` to use
your own.
bambu computes the expected outputs by running `forward_kernel.c` on the host.
See [c_to_verilog_verilog_tb.mk](../../../scripts/mkinc/c_to_verilog_verilog_tb.mk)
and, for the SST run,
[pytorch-to-verilog/3mm-no_weights](../../pytorch-to-verilog/3mm-no_weights/README.md#running-the-testbench-under-sst).

### With bambu dev/panda

The `bambu-devpanda-tb` targets do the same with the bambu on upstream's `dev/panda` branch
(branch `spike/devpanda-macos-testbench` of `tdysart/PandA-bambu`, which builds on macOS and
has its own `--testbench-style=verilog`). They run this directory's C testbench
(`forward_kernel_testbench.c`) natively to record the memory images and the reference results,
and the Verilog testbench replays them, so no XML test vector is needed. The kernel declares
its `m_axi` interfaces in the form `dev/panda` reads, next to the older one.

```sh
make output/bambu-devpanda-tb/baseline/08_sst_results.txt \
  BAMBU_DEVPANDA=/path/to/install-devpanda19/bin/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

`07_results.txt` stops after bambu's Verilator simulation. Expect 26322 cycles both there and
under SST. See [c_to_verilog_devpanda_tb.mk](../../../scripts/mkinc/c_to_verilog_devpanda_tb.mk).

