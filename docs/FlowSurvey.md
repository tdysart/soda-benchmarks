# Flow survey: examples and models through bambu dev/panda, Verilator and SST

A survey from October 2026 of how far each example, model and benchmark in this repository gets
through the `bambu-devpanda-tb` flow: soda-opt lowering, Verilog from bambu dev/panda, the
DPI-free Verilog testbench simulated with Verilator, and the same testbench run under SST with
verilator-sst. How to run the flow is in [PureVerilogTestbench.md](PureVerilogTestbench.md); bambu itself, and
how its testbench works, are in `MACOS_PORT.md` of the
[bambu branch](https://github.com/tdysart/PandA-bambu/blob/spike/devpanda-macos-testbench/MACOS_PORT.md).
Everything here ran on macOS arm64 with the tools built as described in
[ModelConversionTools.md](ModelConversionTools.md).

"Pass" means the hardware's results matched the reference model bit for bit
(`07_results.txt` starts with `1`), with the cycle count shown. The reference model is the C
testbench's own function where the example has one, and otherwise the soda-opt LLVM IR compiled
natively (see [How the reference is chosen](#how-the-reference-is-chosen)).

## Results

### Pass under Verilator

| Example | Input | Cycles |
|---|---|---|
| `examples/c-to-verilog/3mm` | C | 26,322 |
| `examples/pytorch-to-verilog/3mm-no_weights` (transformed) | PyTorch | 10,237 |
| `examples/pytorch-to-llvm` (ToyCNN) | PyTorch | 38,997 |
| `examples/pytorch-to-gds/mm-no_weights` | PyTorch | 986 |
| `models/tensorflow/EELS` | TensorFlow | 2,811,439 |
| `models/tflite/anomaly_detection` | TFLite | 1,122,039 |
| `models/tflite/keyword_spotting` | TFLite | 19,836,263 |
| `models/tflite/image_classification` | TFLite | 56,956,711 |
| `models/tflite/visual_wake_words` | TFLite | 62,562,164 |
| 13 PolyBench kernels through `sb_cli` (MINI, float32, baseline) | PyTorch | 10,756 to 367,000 |

The PolyBench kernels are atax, bicg, doitgen, gemm, gemver, gesummv, mvt, symm, syr2k, syrk,
threemm, trmm and twomm. They were run before the buffer deallocation change described below,
with 10,756 (gesummv) to 367,000 (syr2k) cycles; the two re-run afterwards, gemm (123,484) and
threemm (188,661), moved by under 0.3%.

The GDS example only ran as far as simulation: its last step needs OpenROAD and Yosys, which
are not installed here.

### SST

Run under SST (verilator-sst), the pure-Verilog testbench passed with exactly the cycle count of
the native Verilator run for: all 13 PolyBench kernels, `pytorch-to-llvm`, `pytorch-to-gds`,
`pytorch-to-verilog` (10,237), EELS and `anomaly_detection`. Those SST runs are 2 to 6 minutes
each, mostly the verilator-sst build. The three large TFLite models were not run under SST.

### Synthesized to Verilog but not simulated

| Model | Why |
|---|---|
| `models/pytorch/resnet18` | only `06_verilog.v` was generated; far too many cycles to simulate |
| `models/pytorch/mobilenetv3_small` | same |
| `models/pytorch/squeezenet` | needs about 25 MB of live buffers; bambu's heap is 384 KiB (see below). Its simulation was stopped. |

Verilator runs at about 39,000 cycles per second on this machine, so a 60M-cycle simulation
takes about 25 minutes.

## How the reference is chosen

The testbench C file calls the top function. bambu compiles the design sources natively as the
reference model and replays the recorded inputs and expected outputs in the Verilog testbench.
For LLVM IR input there is no C to run, so:

* If the testbench file defines the top function itself (as `pytorch-to-verilog`'s
  `reference_testbench.c` does), that definition is the reference.
* Otherwise, the soda-opt IR is compiled natively with the top function renamed, and it is the
  reference. This checks that the hardware computes what the IR says; it does not check the
  IR against PyTorch or TensorFlow. This is what the models and PolyBench kernels use, with
  soda-opt's generated `output/forward_kernel_testbench.c` as the driver.

## What had to be fixed to get here

| Problem | Where | Fix |
|---|---|---|
| The hardware ran with zero weights (EELS returned all zeros) | PandA-bambu capture runtime | `mdpi_wrapper.h` now writes the memory-mapped internal globals (weights, constants) into `tb_init.mem` |
| No reference model for IR-only models | PandA-bambu `launch.sh` | use the IR compiled natively when the testbench does not define the top function |
| `sed -i` fails on macOS | `tflite_to_tosa.sh`, `link_memref_copy.sh` | BSD-compatible `-i.bak` |
| `tosa.reshape` rejected by the soda-opt LLVM | `tflite_to_tosa.sh` | `tf-opt` prints the infer-this-dimension marker as INT64_MIN; rewritten to -1 |
| bambu cannot lower `llvm.objectsize` | `link_memref_copy.sh` | compile `memref_copy.c` with `-D_FORTIFY_SOURCE=0 -fno-builtin` |
| Apple clang 21 emits IR that LLVM 19's `opt` cannot read | `link_memref_copy.sh` | use a clang of the same major version as `opt` (Homebrew `llvm@19`) |
| No `roundevenf` in any bambu libm | `link_memref_copy.sh`, `scripts/lib/roundeven.c` | link a definition into the IR and call it in place of `llvm.roundeven` |
| No functional unit for `sqrtf` (batch norm) | `c_to_verilog_devpanda_tb.sh` | pass `-lm` (`BAMBU_LIBM`); `-lm` is still a bambu option |
| bambu fails with `not expected from S_<n> to S_<m>` | `c_to_verilog_devpanda_tb.sh` | the `-MP` setups fail in the mux connection binding on large designs (keyword_spotting, visual_wake_words); the script retries with `BAMBU-BALANCED` |
| Simulations that never finish | `tosa_to_linalg.sh`, `scripts/early_dealloc.py` | see the next section |
| soda-opt overwrote `pytorch-to-verilog`'s handwritten `forward_kernel_testbench.c` | that example | renamed to `reference_testbench.c` |

### The heap

Three of the TFLite models first never finished simulating: they ran past bambu's 200M-cycle
cap, and `image_classification` past 2 billion. The cause was bambu's `malloc`, not the
testbench:

* soda-opt's bufferization gives every intermediate tensor its own `memref.alloc`, which
  becomes a `malloc` in the IR. The pipeline did not free any of them: the pass that inserts
  deallocations had been removed ("passes that break the flow", commit `c3fe30e`).
* In the hardware, `malloc` is synthesized logic with a fixed 384 KiB pool
  (`etc/libbambu/memmgr.c`, compiled into `libbambu.a`) that returns NULL silently when it is
  exhausted. The design does not fail; it runs on with a null pointer until the cycle cap.
* The native reference run uses the host `malloc`, which has gigabytes, so it always worked.

The total malloc'd bytes in the IR matched the failures: `anomaly_detection` 28 KB and EELS
passed, while `keyword_spotting` (622 KB), `image_classification` (1.08 MB),
`visual_wake_words` (2.2 MB) and `squeezenet` (202 MB) did not. Raising `POOL_SIZE` to 8 MiB in
a rebuilt `libbambu.a` made `keyword_spotting` pass (19,836,892 cycles), which confirmed it.

The fix is in the flow, not the pool. `tosa_to_linalg.sh` now runs
`--buffer-deallocation-pipeline`, which works with LLVM 19.1.5's `mlir-opt` but frees every
buffer at the end of the function, so the peak is unchanged. `scripts/early_dealloc.py` then
moves each `memref.dealloc` to right after the last use of its buffer or of any view of it. For
`keyword_spotting` this cut the peak from 631 KB to 76 KB; `image_classification` and
`visual_wake_words` peak at about 197 KB and 221 KB. `squeezenet` still needs about 25 MB.

## Reproducing

The make targets, variables and prerequisites are in
[PureVerilogTestbench.md](PureVerilogTestbench.md). The environment used for this survey:

```bash
source tjd_addpath.sh                      # tools; adds the dev/panda bambu to PATH
export PATH=$HOME/SSTstable/sst16.0/elements-install/bin:$HOME/SSTstable/sst16.0/core-install/bin:$PATH
export PYTHONPATH=$HOME/SODA-OPT/torch-mlir/build/tools/torch-mlir/python_packages/torch_mlir
source $HOME/SODA-OPT/torch-mlir/venv/bin/activate      # torch and torchvision
```

The TensorFlow model used a separate venv with tensorflow 2.16.2 and `tf_keras`, first on `PATH`,
with `TF_USE_LEGACY_KERAS=1`. In each directory:
`make output/bambu-devpanda-tb/baseline/07_results.txt` (`transformed` for `pytorch-to-verilog`),
and `08_sst_results.txt` with `VERILATOR_SST_SRC` for the SST runs. The PolyBench kernels were
scaffolded as described under "Models and PolyBench kernels" there.

## Open items

* `squeezenet` cannot run: its live buffers are about 25 MB. It needs smaller inputs, a larger
  heap, or on-chip buffers instead of a heap.
* `resnet18` and `mobilenetv3_small` were not simulated.
* `early_dealloc.py` rewrites the MLIR text and assumes one function with one block. A
  soda-opt pass would be sturdier.
* bambu's pool size is hard-coded and exhausting it is silent. Making it configurable, or
  warning, would turn this class of failure into an error message.
* Making the buffers static (global memories with planned reuse) would suit hardware better
  than a synthesized heap.
* `sb_cli` should generate the `bambu-devpanda-tb` targets itself.
* Not covered: the IP-integration recipes (assert, change-location, hw-counters, vector-dot),
  the esp and cpu backends, and the soda-plugins dataflow lit tests.
* One LLVM for every tool: Homebrew's `llvm@19` lacks the MLIR test libraries soda-opt links.
  `scripts/external/setup-llvm.sh` is a draft that builds LLVM 19.1.5 with clang, MLIR and
  RTTI; it has not been run.
