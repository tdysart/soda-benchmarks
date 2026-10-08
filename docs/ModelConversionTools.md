# Building the model conversion tools: `torch-mlir-opt` and the TensorFlow MLIR tools

The flows that start from a PyTorch or TensorFlow/TFLite model need front-end tools that
turn the model into TOSA MLIR, which the LLVM 19.1.5 `mlir-opt` and soda-opt then lower.
The Docker image ships these; without Docker you build them yourself. This page covers
building them natively on macOS/arm64 from pinned upstream commits.

| Tool | Used by | Built by |
|------|---------|----------|
| `torch-mlir-opt` and the `torch_mlir` Python package | the PyTorch examples (`examples/pytorch-to-*`) | [setup-torch-mlir.sh](../scripts/external/setup-torch-mlir.sh) |
| `tf-opt`, `tf-mlir-translate`, `flatbuffer_translate` | [tflite_to_tosa.sh](../scripts/tflite_to_tosa.sh), [graphdef_to_tosa.sh](../scripts/graphdef_to_tosa.sh) | [setup-tensorflow-mlir.sh](../scripts/external/setup-tensorflow-mlir.sh) |

Neither needs a fork or a patch: both scripts fetch an unmodified upstream commit and work
around macOS problems with build flags only.

## Why these exact commits

Both projects build their own copy of LLVM, and the TOSA they print has to parse with the
LLVM 19.1.5 `mlir-opt` that soda-opt is built against (see
[Toolchain versions](PureVerilogTestbench.md#toolchain-versions)). TOSA's textual form changes
between LLVM releases, so the closest LLVM wins:

| Project | Commit | Its LLVM | Why |
|---------|--------|----------|-----|
| torch-mlir | `43506726853b` (2024-08-08) | submodule `d16b21b` (2024-06-27) | the last commit before it moved its LLVM past the `release/19.x` branch point |
| TensorFlow | `d7f515cc2fd8` (2024-07-23) | `acc159aea1e6` (2024-07-23) | its LLVM pin is the day `release/19.x` branched (`f2ccf80136a0`). TF 2.17.0 pins a 2024-05-31 LLVM and 2.18.0 a 2024-09-23 one, so neither release is as close |

If soda-opt ever moves to a different LLVM, pick new commits the same way: find the LLVM
commit you want, then the project commit that pins nearest to it (for TensorFlow, the
history of `third_party/llvm/workspace.bzl`, which is where `LLVM_COMMIT` lives).

## Prerequisites

* macOS with the Command Line Tools. A full Xcode is **not** needed; the TensorFlow script
  detects its absence and switches Bazel to the plain C++ toolchain.
* `git`, `curl`, `cmake`, `ninja` and `python3.12` (Homebrew: `brew install cmake ninja python@3.12`).
  Python 3.12 matters: torch 2.4.0 has wheels up to 3.12, and the TensorFlow commit has Bazel
  lock files for 3.9 to 3.12 only. Do not let a newer `python3` be picked up.
* Disk: about 5 GB for torch-mlir, and about 15 GB for TensorFlow, 13 GB of which is the
  Bazel cache that can be deleted once the tools are copied out (see below).
* Time, on 14 cores: about 10 minutes for torch-mlir and about 30 minutes for TensorFlow.
* To check the result you also need the LLVM 19.1.5 `mlir-opt` on `PATH`.

Nothing needs to be installed system-wide. The TensorFlow script downloads the Bazel version
the commit asks for (6.5.0) into its work directory and checks it against Bazel's published
SHA-256.

## 1. torch-mlir

```sh
PYTHON=python3.12 ./scripts/external/setup-torch-mlir.sh ../torch-mlir
```

The argument is the work directory; it defaults to `builds/torch-mlir` inside this repo. The
examples in these docs use `../torch-mlir`, next to `llvm`, `soda-opt` and the other tool builds.
Inside it the script creates:

| Path | Contents |
|------|----------|
| `torch-mlir/` | the source checkout, plus its `llvm-project` and `stablehlo` submodules |
| `venv/` | a Python 3.12 venv with CPU torch 2.4.0 |
| `build/` | the CMake/Ninja tree; `build/bin/torch-mlir-opt` |

Notes:

* The commit's `requirements.txt` pins `torch==2.5.0.dev20240804`, a nightly that no longer
  exists. The script installs the latest stable torch of that time, 2.4.0, which is what the
  commit's own "stable" CI leg used. The importer is compiled against that torch, so keep the two matched.
* It builds only torch-mlir and the parts of LLVM it needs, not all of LLVM.
* Environment variables for pinning, build type and parallelism are listed at the top of the script.

Put it on your path:

```sh
export PATH=$PWD/../torch-mlir/build/bin:$PATH
export PYTHONPATH=$PWD/../torch-mlir/build/tools/torch-mlir/python_packages/torch_mlir:$PYTHONPATH
source ../torch-mlir/venv/bin/activate     # the Python that has torch
```

## 2. TensorFlow MLIR tools

```sh
PYTHON=python3.12 ./scripts/external/setup-tensorflow-mlir.sh
```

The work directory defaults to `../tensorflow` (pass one as the first argument to change it).
Inside it:

| Path | Contents |
|------|----------|
| `tensorflow/` | the source checkout (a single shallow-fetched commit) |
| `bin/` | the pinned Bazel (`bazel-6.5.0`, plus a `bazel` symlink), then the finished tools |
| `cache/` | Bazel's output base and disk cache (about 13 GB) |

The script, in order:

1. fetches the pinned TensorFlow commit and checks that its `.bazelversion` matches;
2. downloads and checksums that Bazel into `bin/`;
3. runs TensorFlow's `./configure` with every optional backend (CUDA, ROCm, Android, iOS, XLA) off;
4. builds `//tensorflow/compiler/mlir:tf-opt`, `//tensorflow/compiler/mlir:tf-mlir-translate`
   and `//tensorflow/compiler/mlir/lite:flatbuffer_translate`;
5. copies the three binaries and `libtensorflow_framework` into `bin/` and runs `--version` on each.

The tools link `libtensorflow_framework.2.dylib` dynamically. Their rpaths include
`@loader_path`, so the library only has to sit in the same directory; that is why `bin/`
holds it too. Keep the tools and the library together if you move them.

Put it on your path:

```sh
export PATH=$PWD/../tensorflow/bin:$PATH
```

Once `bin/` is populated you can delete `cache/` and `tensorflow/` to reclaim the disk space
if you do not plan to rebuild; the binaries in `bin/` do not depend on them. Rerunning the
script after that starts the whole build over.

### macOS-specific workarounds

These are all in the script, as Bazel flags and environment variables, so you should not
have to do anything. They are listed because each one shows up as a confusing error if you
build TensorFlow by hand on a current Mac:

| Symptom | Cause | What the script does |
|---------|-------|----------------------|
| `Cannot find bazel. Please install bazel/bazelisk.` | `./configure` looks for `bazel` on `PATH`, not a versioned name | symlinks `bazel` and prepends `bin/` to `PATH` |
| `Specified python version: 3.14` ... `no such package '@python_version_repo//'` | Bazel follows the newest `python3`, and the commit has no lock file for it | exports `HERMETIC_PYTHON_VERSION=3.12` |
| `Xcode version must be specified to use an Apple CROSSTOOL` | only the Command Line Tools are installed | sets `BAZEL_USE_CPP_ONLY_TOOLCHAIN=1` as an environment variable **and** `--repo_env`, and `--extra_toolchains=@local_config_cc_toolchains//:all`. The variable alone is not enough: Bazel still resolves the Apple toolchain unless the plain one is given priority |
| `'is_signed' cannot be specialized: Users are not allowed to specialize this standard library entity` | recent macOS SDKs mark libc++ traits as non-specializable, and TensorFlow specializes `std::is_signed` for its quantized types | adds `--copt` and `--host_copt` `-Wno-invalid-specialization` (the error is a default-on warning; `--host_copt` is needed because it also hits tools built for the host) |
| `dyld: Library not loaded: @rpath/libtensorflow_framework.2.dylib` | the tools were copied out of Bazel's tree | copies the library next to them |

If you have a full Xcode installed, the Xcode workaround is skipped automatically.

## 3. Check that it works

Run a model through the same flags `tflite_to_tosa.sh` uses, then through the repo's lowering,
using the LLVM 19.1.5 `mlir-opt`:

```sh
flatbuffer_translate -tflite-flatbuffer-to-mlir -mlir-print-local-scope \
  -emit-builtin-tflite-ops -lower-tensor-list-ops \
  models/tflite/anomaly_detection/anomaly_detection.tflite -o /tmp/00_tfl.mlir

tf-opt -tf-executor-to-functional-conversion -tf-region-control-flow-to-functional \
  -tf-shape-inference -tf-to-tosa-pipeline -tfl-to-tosa-pipeline -tf-tfl-to-tosa-pipeline \
  -tosa-legalize-tfl -tosa-strip-quant-types -tosa-tflite-verify-fully-converted \
  /tmp/00_tfl.mlir -o /tmp/01_tosa.mlir

mlir-opt -pass-pipeline="builtin.module(func.func(tosa-to-arith, tosa-to-tensor, tosa-to-linalg-named, tosa-to-linalg))" \
  /tmp/01_tosa.mlir -o /tmp/02_linalg.mlir
grep -c 'linalg\.' /tmp/02_linalg.mlir        # 82 for this model
```

Expect no errors from any of the three commands. Two things to know:

* **Keep `-tosa-strip-quant-types`.** The model is quantized. Without that pass `01_tosa.mlir` still
  contains `!quant.uniform` types, which parse fine but make the 19.1.5 `mlir-opt` assert
  (`only integers and floats have a bitwidth`) in `tosa-to-linalg`. That is the pipeline
  being incomplete, not a version mismatch.
* The version banner of the TF tools says `LLVM version 19.0.0git`, because that is a development
  snapshot taken at the branch point. It is expected and is not a 19.1 build.

For torch-mlir, `torch-mlir-opt --version` and the `torch_mlir` import are the script's own
smoke test. A full check is to run one of the `examples/pytorch-to-*` examples.

## Using them with the scripts

[check_docker.sh](../scripts/check_docker.sh) is sourced by the conversion scripts. When `docker`
is not installed it requires `flatbuffer_translate`, `tf-mlir-translate`, `tf-opt` and
`torch-mlir-opt` (plus soda-opt, mlir-opt, mlir-translate and bambu) to be on `PATH`, and
stops with an error naming the first missing one. With Docker present the scripts run
the same tools inside the `agostini01/soda` image instead, and nothing here is needed.

## Rebuilding and updating

* **Rebuild after editing TensorFlow sources:** rerun the script. Bazel's cache makes it incremental.
* **Change the commit:** `TF_COMMIT=<sha> ./scripts/external/setup-tensorflow-mlir.sh`. The
  script stops if that commit wants a Bazel other than 6.5.0; update `BAZEL_VERSION` in
  the script (and expect to revisit the macOS workarounds above) in that case. The
  torch-mlir equivalent is `TORCH_MLIR_COMMIT`.
* **Need to change TensorFlow itself:** keep a small patch file in `scripts/external/` and apply
  it in the script, as for llvm-cbe, rather than maintaining a fork.
