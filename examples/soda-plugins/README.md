# SODA Plugins

Provide a intree way of compiling mlir-opt plugins to be used with soda-benchmarks.


## Project Structure

- `soda-plugins/` - Contains the source code for the plugins library.
- `lib/` - Contains the implementation of passes.
- `include/` - Contains the declarations of passes.


## Building

We prefer the component build approach, which allows you to build the plugins as a separate library that can be linked against the `soda-opt` or `mlir-opt` tool.

To build the plugins, run the following commands:

```sh
mkdir build && cd build

cmake -G Ninja .. \
  -DMLIR_DIR=/opt/llvm-project/lib/cmake/mlir \
  -DLLVM_EXTERNAL_LIT=/workspaces/soda/builds/llvm-project/build/bin/llvm-lit

cmake --build . --target SODAPlugin
```

`SODAP_BAMBU_ROOT` can be specified to enable Bambu specific passes.
To do that, add `-DSODAP_BAMBU_ROOT=<path/to/bambu>` (the directory holding `settings.sh`)
when configuring the compilation build with cmake.
Without it the plugin still builds, with a warning, and the Bambu tests are
reported as unsupported.


## Testing

If tests are enabled and llvm-lit is available, you can run the tests with:

```sh
cmake --build . --target check-sodap
```


##  Running the Plugins

To run the plugins, you can use the `mlir-opt` tool with the `--load-pass-plugin` option to load the pass plugin library or the `--load-dialect-plugin` option to load the dialect plugin libray. We compile both in a single file which is available in the `build` directory under `lib/SODAPlugin.so`.

One of the included passes in the plugin is `soda-view-op-graph`, which generates graphviz output of the operations in the MLIR file. To use this pass, you can run the following command:

```bash
mlir-opt \
  -allow-unregistered-dialect \
  -mlir-elide-elementsattrs-if-larger=2  \
  --load-pass-plugin=/workspaces/soda-benchmarks/examples/soda-plugins/build/lib/SODAPlugin.so \
  --pass-pipeline="builtin.module(soda-view-op-graph)" \
  /workspaces/soda-benchmarks/examples/soda-plugins/test/sodap/print-op-graph.mlir
```


We also include infrastrucure to add extensions to the transform dialect. In this example we added `transform.my.change_call_target`.

```bash
mlir-opt \
  --load-pass-plugin=/workspaces/soda-benchmarks/examples/soda-plugins/build/lib/SODAPlugin.so \
  --load-dialect-plugin=/workspaces/soda-benchmarks/examples/soda-plugins/build/lib/SODAPlugin.so \
  --transform-interpreter \
  /workspaces/soda-benchmarks/examples/soda-plugins/test/sodap/my-extension.mlir 
```


## Lowering dataflow to Verilog with Bambu

The `DataflowToLLVM` passes lower `dataflow` streams to the `ac_channel` ABI that Bambu
recognizes, and emit the `--architecture-xml` file describing the dataflow top, its modules,
and the FIFO bundles between them.

### Requirements

- A Bambu from upstream's `dev/panda` branch. It is the first to accept the `array_dims`
  parameter attribute in `architecture.xml`, and its `ac_channel.h` has no nested `fifo`
  class (channel accesses are `_read_bambu_internal` / `_write_bambu_internal`), which is
  what `ConvertDataflowToLLVM` expects. Bambu 2024.10 and `upstream/main` reject the XML
  (`array_dims`) and then fail to synthesize the channel calls.
- The LLVM that the plugin's IR comes from and the clang Bambu uses must be the same major
  version (opaque pointers): clang 16 cannot read the plugin's LLVM 19 IR.
- `SODAP_BAMBU_ROOT` set at configure time, so the Bambu tests are enabled. Without it
  they are reported as unsupported.

### Flow

Run the backend pipeline on dataflow IR in the call-graph form that
`sodap-dataflow-nodes-to-func` produces (see
`test/sodap/Conversion/DataflowToLLVM/Inputs/gemm_small.mlir`), then translate and link:

```bash
mlir-opt kernel.mlir \
  --load-dialect-plugin=build/lib/SODAPlugin.so \
  --load-pass-plugin=build/lib/SODAPlugin.so \
  --pass-pipeline="builtin.module(sodap-dataflow-to-llvm-pipeline{top-func=forward arch-file=architecture.xml})" \
  -o llvm.mlir
mlir-translate --mlir-to-llvmir llvm.mlir -o kernel.ll
llvm-link -S kernel.ll ac_channel_specializations.ll -o linked.ll
opt linked.ll -passes=always-inline -S -o final.ll
```

The pass writes `ac_channel_specializations.{cpp,ll}` in the working directory. Set
`clangxx=` and `include-panda-path=` on the pipeline to override the defaults compiled in
from `SODAP_BAMBU_ROOT`.

The specialization unit is compiled for a 32-bit target by default, to match Bambu's default
`-m32`. Pass `machine-bits=64` (together with `bambu -m64`) where the host compiler has no
32-bit target, as on arm64 macOS.

### Running Bambu

Pass `--generate-interface=INFER`:

```bash
bambu -m64 final.ll --top-fname=forward --architecture-xml=architecture.xml \
  --generate-interface=INFER --compiler=I386_CLANG19 \
  --device-name=nangate45 --clock-period=5
```

Without `--generate-interface=INFER` Bambu defaults to minimal interface generation, which
forces every interface to `default`. The channel arguments of the dataflow modules are then
never turned into FIFO ports, and synthesis stops with *"Operation for which does not
exist a functional unit ... `_read_bambu_internal`"*.

`-m64` is only needed where the compiler has no i386 target (for example clang on macOS
arm64). `--compiler` must name a clang of the same major version as the LLVM that produced
`final.ll`.

### Building on macOS

The plugin links with `-force_load` on Apple platforms (`ld64` has no `--whole-archive`).
MLIR installs built with the Python bindings need NumPy at configure time; point CMake at
an interpreter that has it with `-DPython3_EXECUTABLE=...`.
