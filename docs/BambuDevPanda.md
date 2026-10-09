# Bambu `dev/panda` on macOS: the `spike/devpanda-macos-testbench` branch

This page covers the branch `spike/devpanda-macos-testbench` of
[tdysart/PandA-bambu](https://github.com/tdysart/PandA-bambu): upstream bambu's `dev/panda`
branch, built natively on macOS/arm64, plus a DPI-free Verilog testbench
(`--testbench-style=verilog`) that runs under Verilator and verilator-sst. It is what the
soda-plugins dataflow designs need, and what the `bambu-devpanda-tb` make targets of the
c-to-verilog examples use.

Status: **experimental.** It works for the cases listed below and has a regression suite, but it
is a spike branch, not something upstream has seen. The branch's own notes, with more detail on
the macOS port, are in `MACOS_PORT.md` at its root.

| Works | Does not (yet) |
|-------|----------------|
| Building bambu, `bambu-cc`, `eucalyptus`, the clang plugins and libbambu on macOS arm64 | `--testbench-style=mdpi` (upstream's DPI simulation) on macOS |
| C and LLVM IR input to Verilog, including soft-float | Internal memory-mapped globals in the testbench |
| `--testbench-style=verilog` with Verilator: array, scalar-port and `m_axi` interfaces, several calls per testbench | Top-level FIFO/AXIS/channel interfaces and return values in the testbench |
| The soda-plugins dataflow design `forward` (FIFOs between nodes), simulated and run under SST | Simulators other than Verilator |
| `make ...bambu-devpanda-tb/...` targets for `3mm`, natively and under SST | The OpenROAD patch step (`patch_openroad_synt.sh`) for the generated Verilog; the `asap7-*` devices (their device files fail to parse, use `nangate45`) |

## Why this branch exists

* Upstream's `main` has not moved since April 2025; development is on `dev/panda`.
* `dev/panda` is the first bambu that accepts what the soda-plugins dataflow lowering emits: the
  `array_dims` attribute in `--architecture-xml`, and the unified `ac_channel.h` (channel accesses
  are `_read_bambu_internal`/`_write_bambu_internal`, with no nested `fifo` class). The bambu
  based on upstream `main` has neither.

## Repositories

| Repository | Branch | Used for |
|------------|--------|----------|
| [tdysart/PandA-bambu](https://github.com/tdysart/PandA-bambu) | `spike/devpanda-macos-testbench` | bambu itself; based on `upstream/dev/panda` at `91bd4639e` |
| [tdysart/soda-benchmarks](https://github.com/tdysart/soda-benchmarks) | `tjd-verilator-sst` | this repo: the scripts, make targets and examples that drive it |
| [tactcomplabs/verilator-sst](https://github.com/tactcomplabs/verilator-sst) | `feature/mdpi-testbench-support` | builds the testbench into an SST component |

[PureVerilogTestbench.md](PureVerilogTestbench.md) ties the three together for a from-scratch run.

## Prerequisites

This was built and tested on macOS 26 (arm64) with Xcode's command line tools and these Homebrew
packages: `llvm@19`, `cmake`, `ninja`, `boost`, `bison`, `flex`, `gmp`, `mpfr`, `verilator`,
`coreutils` and `gawk`. For the SST runs also a built SST and verilator-sst
([PureVerilogTestbench.md](PureVerilogTestbench.md#prerequisites) lists them).

Two choices are not interchangeable:

* **Apple clang builds bambu, Homebrew `llvm@19` is the compiler bambu drives** (`--compiler=I386_CLANG19`).
  bambu loads clang plugins into that compiler, so the plugins must use the same C++ library
  (libc++); building with Homebrew GCC gives libstdc++ and an ABI mismatch.
* **Not `~/SODA-OPT/llvm`.** That LLVM 19.1.5 build is MLIR-only (no clang, static, RTTI off) and
  cannot host the plugins. Clang 16 cannot be used either: it cannot read the LLVM 19 IR that
  soda-opt produces (opaque pointers), and the clang bambu uses has to be the same major version
  as the LLVM that produced the IR.

## 1. Build

```bash
brew install llvm@19
git clone -b spike/devpanda-macos-testbench git@github.com:tdysart/PandA-bambu.git
cd PandA-bambu
git submodule update --init --depth 1

export PATH=/opt/homebrew/opt/llvm@19/bin:$PATH
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_INSTALL_PREFIX=$HOME/bambu-devpanda \
  -DPANDA_ENABLE_WERROR=OFF -DPANDA_ENABLE_OPT=OFF \
  -DPANDA_LIBBAMBU_COMPILER=I386_CLANG19
ninja -C build
cmake --install build
```

The scripts below take the installed `bin/bambu` as `BAMBU_DEVPANDA` and find the rest of the
installation from its path (`$HOME/bambu-devpanda` above; `~/SODA-OPT/panda/install-devpanda19`
on this machine). The configure step should report `clang-19: OK`. Do not install over an existing bambu you still use: the branch
has its own install tree.

## 2. Running bambu by hand

The installed `settings.sh` needs GNU `readlink -e`, which macOS lacks, and the backend scripts
bambu generates use GNU `readlink -e` and gawk too. The scripts in this repo set all of this up;
by hand:

```bash
I=$HOME/bambu-devpanda
mkdir -p /tmp/gnu-shim
ln -sf $(command -v greadlink) /tmp/gnu-shim/readlink     # from coreutils
ln -sf $(command -v gawk) /tmp/gnu-shim/awk
export BAMBU_HLS=$I BAMBU_HLS_BACKEND_PATH=$I
export PATH=/tmp/gnu-shim:$I/bin:/opt/homebrew/opt/llvm@19/bin:$PATH
```

Then call `bambu` with `-m64` (clang has no 32-bit target on arm64 macOS) and
`--compiler=I386_CLANG19`.

Differences from the bambu the older flows use, which break command lines copied from them:

* `-lm`, `--soft-float`, `--verilator-parallel` and `-v3` are no longer options.
* Interface pragmas use the form
  `#pragma HLS interface port=P0 mode=m_axi offset=direct bundle=gmem0`. The older
  `#pragma HLS_interface P0 m_axi direct` is silently ignored, which shows up as bambu inferring a
  scalar interface and refusing the kernel ("pointer is written before it is read").
* Dataflow designs need `--generate-interface=INFER`; see section 5.

## 3. `--testbench-style=verilog`

```bash
bambu -m64 kernel.c --top-fname=kernel --compiler=I386_CLANG19 --device-name=nangate45 \
  --clock-period=5 --simulate --simulator=VERILATOR --testbench-style=verilog \
  --generate-interface=INFER --generate-tb=kernel_testbench.c
```

`--testbench-style` is `mdpi` (upstream's, the default) or `verilog`. With `verilog`, only
Verilator is supported. bambu then:

1. **Captures.** Builds your C testbench against a capture runtime that stands in for libmdpi,
   and runs it natively. At each call of the top function the generated wrapper records the
   memory the hardware will see (`tb_init.mem`) and runs the original C as the reference
   (`tb_expected.mem`). The reference result is handed back to your testbench as if the hardware
   had produced it, so its own checks pass and a later call that reads an earlier output works.
2. **Replays.** Verilates the generated testbench with `BAMBU_TB_VERILOG` defined, which makes
   its library components use an in-simulation memory (`tb_shim_pkg`) instead of the five DPI
   functions that normally call into the host. Before each call the shim loads that call's input
   image, and afterwards compares the memory with the expected image.
3. **Reports.** The cycle counts and the pass/fail code flow back through bambu's normal
   `Evaluation` step (`Total cycles`, `Number of executions`); the testbench prints each mismatch
   (`Sim: MISMATCH ...`) and the backend script exits with the simulation's status.

The testbench is a self-contained module with a single `clock` port, which is why it can run
under verilator-sst. The image formats and the code are documented in
`etc/libtech/backend/simulation/verilator_verilog/` and `MACOS_PORT.md` in the branch.

What your C testbench has to look like:

* It is the same file the MDPI flow uses. It calls the top function and may check the result.
* The top function may be defined in the same file as `main`; it is made weak for the link.
* A pointer parameter whose type does not give its size (`void*`) needs
  `m_param_alloc(index, bytes)` before the call, as for the MDPI flow
  (`#ifdef __BAMBU_SIM__ #include <mdpi/mdpi_user.h>`). Without it the generated wrapper's
  placeholder size (4 bytes) is all the capture knows about the buffer.
* If the design comes from LLVM IR there is no C to run as the reference model, so the testbench
  file's own definition of the top function is used for that. See section 5.

## 4. The c-to-verilog examples and SST

The [3mm](../examples/c-to-verilog/3mm/README.md#pure-verilog-testbench) C example and the
[PyTorch 3mm](../examples/pytorch-to-verilog/3mm-no_weights/README.md#pure-verilog-testbench)
example have a `bambu-devpanda-tb` set of targets next to the existing `bambu` ones:

```bash
cd examples/c-to-verilog/3mm
make output/bambu-devpanda-tb/baseline/08_sst_results.txt \
  BAMBU_DEVPANDA=$HOME/bambu-devpanda/bin/bambu \
  VERILATOR_SST_SRC=/path/to/verilator-sst \
  SST=/path/to/sst-install/bin/sst
```

| Target | What it produces |
|--------|------------------|
| `06_verilog.v` | the Verilog |
| `07_results.txt` | also simulates with Verilator (`<1\|0><TAB><cycles>`) |
| `08_sst_results.txt` | runs the testbench under SST via verilator-sst (`<1\|0> <cycles>`) |

The C example passes in 26322 cycles natively and under SST, the PyTorch one in 23160. The scripts behind the targets:
[c_to_verilog_devpanda_tb.sh](../scripts/c_to_verilog_devpanda_tb.sh) (bambu; set `BAMBU_M`,
`BAMBU_COMPILER` or `CLANG_BIN` if your setup differs) and
[verilator_sst_devpanda_tb.sh](../scripts/verilator_sst_devpanda_tb.sh), which also works on
any bambu output directory made with `--testbench-style=verilog`:

```bash
VERILATOR_SST_SRC=/path/to/verilator-sst SST=/path/to/sst \
  scripts/verilator_sst_devpanda_tb.sh <bambu_dir> results.txt
```

verilator-sst's custom-module build takes one top source, so that script concatenates the shim
package, `panda_libtech.v`, the design and the testbench into one file. It exits non-zero if the
testbench reports a mismatch.

## 5. Dataflow designs from soda-plugins

The soda-plugins backend ([examples/soda-plugins](../examples/soda-plugins/README.md)) lowers a
dataflow MLIR module to LLVM IR plus an `architecture.xml`. Using it with this bambu:

1. Run the pipeline with `machine-bits=64` (the default, `-m32`, has no sysroot on arm64 macOS):
   `sodap-dataflow-to-llvm-pipeline{top-func=forward ... machine-bits=64}`, with `clangxx` and
   `include-panda-path` pointing at the `llvm@19` clang++ and `<install>/include/panda`.
2. Write a C testbench whose `main` calls the top function and whose definition of the top
   function is the reference model (the IR cannot run natively: its `ac_channel` operations only
   exist in hardware).
3. Run bambu on the IR with `--architecture-xml=architecture.xml --generate-interface=INFER
   --generate-tb=<testbench.c> --testbench-style=verilog` and the options from section 3.

Without `--generate-interface=INFER` bambu defaults to minimal interface generation, forces every
interface to `default`, and synthesis stops with "no functional unit ... `_read_bambu_internal`".

The soda-plugins `forward` design (`D = 0.5*(A*B) + 0.1f*C`, three nodes joined by FIFOs) runs in
1849 cycles, natively and under SST, and all output words match the reference bit for bit. Its
IR, architecture XML and testbench are the `dataflow_forward` case of the branch's regression.

## 6. Tests

`panda_regressions/hls/bambu_verilog_testbench/run.sh [install_dir]` in the PandA-bambu branch
synthesizes and replays four cases (`vadd`, a testbench with three calls including one that
consumes an earlier output, an `m_axi` kernel with two calls, and the dataflow `forward`), then
corrupts one expected word of each and checks the failure is reported and the return code is 1.
It sets up the GNU shims itself and needs the install, Verilator and `llvm@19`.

The plugin's own tests (`check-sodap`) skip the Bambu-dependent cases (`REQUIRES: panda`) here:
they need `SODAP_BAMBU_ROOT`, whose defaults assume a `compilers/clang-19` directory and the
plugin's 32-bit target. The `machine-bits` option was checked by hand.

## Troubleshooting

* **`clang-19: command not found`.** Put `/opt/homebrew/opt/llvm@19/bin` on `PATH`
  (the scripts do, via `CLANG_BIN`).
* **`readlink: illegal option -- e` or an awk syntax error in `xmlq`.** The GNU shims from
  section 2 are missing.
* **`unrecognized option '--soft-float'` (or `-lm`, `-v3`).** Dropped from `dev/panda`; remove
  them.
* **`uses inferred scalar pointer interface 'ovalid' but the pointer is written before it is
  read`.** The interface pragmas are in the old syntax; use `#pragma HLS interface port=...`.
* **The soda-plugins pass fails compiling the specialization unit (`ldiv_t`, `mbstate_t` not
  found).** It compiled for a 32-bit ARM target; pass `machine-bits=64`.
* **`capture: ... is not supported by the verilog testbench style`.** The top function uses an
  interface the capture step cannot record yet (FIFO/AXIS, channels, return values, banked,
  internal memory-mapped variables). The message names it.
* **A pointer parameter's buffer is cut short in the images, or the replay mismatches on a
  `void*` parameter.** Add `m_param_alloc(N, bytes)` for it to the testbench (section 3).
* **The SST run reports no result.** Raise `SST_CYCLES` (default: bambu's cycle count plus 10%),
  and check `<bambu_dir>/verilator-sst/sst-run.log`.
* **Installing over an existing bambu.** Use a separate `CMAKE_INSTALL_PREFIX`; the tools are
  named `bambu` in every install, so keep them apart on `PATH`.

## Maintaining the branch

The branch is a handful of commits on top of `upstream/dev/panda` (`git log
upstream/dev/panda..HEAD`): the macOS portability fixes (CMake, libc++ source fixes, glibc-isms in
libbambu, BSD tool differences), then the testbench style (`BambuParameter.cpp`,
`NC_TESTBENCH_IPs.xml`, the `verilator_verilog` backend directory) and the regression. To follow
upstream, rebase onto `upstream/dev/panda`; the places most likely to conflict are the CMake files
and `NC_TESTBENCH_IPs.xml`. Re-run the regression afterwards.
