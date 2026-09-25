#!/usr/bin/env python3
"""Build a bambu XML test vector from soda-opt's generated C testbench.

soda-opt's -soda-extract-arguments-to-c-testbench writes a
forward_kernel_testbench.c that declares one `<type> P<i>_temp[] = {...};`
array per kernel argument, in call order. This reads those declarations for
each argument's element type and length, and emits a bambu XML test vector
(the `--generate-tb=<file.xml>` input of bambu's self-contained, non-DPI
testbench) with random values for the inputs and zeros for the outputs.

The XML attribute names are the kernel's parameter names as bambu sees
them. For C produced by ll_to_c_cbe.sh (llvm-cbe) those are _1.._N; for
LLVM IR given to bambu 2024 directly they are P0..P<N-1>
(--param-prefix P --param-base 0).

With --arch-xml it also writes a bambu --architecture-xml file that gives each
parameter its C type (e.g. float*). bambu 2024's pure-Verilog testbench
(--testbench-style=verilog) needs it for LLVM IR input: with opaque pointers
the IR only says ptr, and bambu would otherwise see every pointer as void*.

With --expected-from it also runs the kernel on the host (an LLVM IR file,
compiled with llc, or a C file) on the generated inputs and adds the output
arguments' results as expected values (<param>:output). The testbench then
checks them. bambu 2024's --testbench-style=verilog computes missing expected
values itself, so this is mainly useful to cross-check it.

Usage:
    testbench_to_xml.py forward_kernel_testbench.c -o test.xml
    testbench_to_xml.py forward_kernel_testbench.c -o test.xml --outputs 3,4 --seed 7
    testbench_to_xml.py forward_kernel_testbench.c -o test.xml --param-prefix P --param-base 0 \
        --arch-xml architecture.xml --expected-from 05_llvm_transformed.ll
"""

import argparse
import ctypes
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

ARRAY_RE = re.compile(r"\b([A-Za-z_][\w ]*?)\s+P(\d+)_temp\[\]\s*=\s*\{([^}]*)\}")
CTYPES = {"float": ctypes.c_float, "double": ctypes.c_double,
          "char": ctypes.c_int8, "short": ctypes.c_int16, "int": ctypes.c_int32, "long": ctypes.c_int64,
          "int8_t": ctypes.c_int8, "int16_t": ctypes.c_int16, "int32_t": ctypes.c_int32, "int64_t": ctypes.c_int64,
          "uint8_t": ctypes.c_uint8, "uint16_t": ctypes.c_uint16, "uint32_t": ctypes.c_uint32,
          "uint64_t": ctypes.c_uint64}
INT_TYPES = ("int", "long", "short", "char", "int8_t", "int16_t", "int32_t", "int64_t",
             "uint8_t", "uint16_t", "uint32_t", "uint64_t")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("testbench", help="soda-opt generated C testbench (forward_kernel_testbench.c)")
    parser.add_argument("-o", "--output", required=True, help="Path to write the XML test vector")
    parser.add_argument("--outputs", default=None,
                        help="Comma-separated argument indices (0-based) that are outputs and get zeros "
                             "(default: the last argument)")
    parser.add_argument("--param-prefix", default="_", help="Parameter name prefix (default: _)")
    parser.add_argument("--param-base", type=int, default=1,
                        help="Number of the first parameter (default: 1, i.e. _1 for llvm-cbe)")
    parser.add_argument("--arch-xml", default=None,
                        help="Also write a bambu --architecture-xml file with the parameters' C types")
    parser.add_argument("--expected-from", default=None, metavar="KERNEL",
                        help="Run this kernel (.ll or .c) on the host and add the outputs' expected values")
    parser.add_argument("--kernel-name", default="forward_kernel",
                        help="Kernel symbol for --arch-xml (default: forward_kernel)")
    parser.add_argument("--seed", type=int, default=42, help="random.seed() value, for reproducible vectors")
    parser.add_argument("--low", type=float, default=1.0, help="Lower bound for generated values")
    parser.add_argument("--high", type=float, default=5.0, help="Upper bound for generated values")
    parser.add_argument("--decimals", type=int, default=3, help="Decimal places for floating-point values")
    return parser.parse_args()


def run_on_host(args, params, values, outputs):
    """Compile args.expected_from into a shared library, call the kernel on values and return the outputs."""
    cc = os.environ.get("CC", "cc")
    with tempfile.TemporaryDirectory() as tmp:
        lib = os.path.join(tmp, "kernel.so")
        if args.expected_from.endswith(".ll"):
            llc = os.environ.get("LLC", "llc")
            if not shutil.which(llc):
                sys.exit(f"ERROR: {llc} not found; set LLC to an llc that reads {args.expected_from}")
            obj = os.path.join(tmp, "kernel.o")
            subprocess.check_call([llc, "-O0", "-filetype=obj", "--relocation-model=pic", args.expected_from,
                                   "-o", obj])
            subprocess.check_call([cc, "-shared", obj, "-o", lib])
        else:
            subprocess.check_call([cc, "-O0", "-ffp-contract=off", "-shared", "-fPIC", "-w", args.expected_from,
                                   "-o", lib])
        kernel = getattr(ctypes.CDLL(lib), args.kernel_name)
        bufs = []
        for (idx, ctype, count), vals in zip(params, values):
            base = ctype.split()[-1]
            if base not in CTYPES:
                sys.exit(f"ERROR: --expected-from does not support argument type {ctype}")
            bufs.append((CTYPES[base] * count)(*vals))
        kernel.argtypes = [ctypes.c_void_p] * len(bufs)
        kernel(*bufs)
        return {idx: list(bufs[idx]) for idx in outputs}


def format_values(vals):
    # repr() keeps full precision: the testbench compares floats bit-exactly (to a few ULP)
    return "{" + ",".join(repr(v) for v in vals) + "}"


def write_arch_xml(args, params):
    """Write a bambu architecture XML declaring each (pointer) parameter's C type, in the format of the
    architecture.xml that bambu's clang plugin writes for C input."""
    bundles, parms = [], []
    for idx, ctype, _ in params:
        name = f"{args.param_prefix}{idx + args.param_base}"
        bundles.append(f'         <bundle name="{name}" mode="default"/>')
        parms.append(f'         <parameter port="{name}" index="{idx}" bundle="{name}" '
                     f'typename="{ctype}*" original_typename="{ctype}*"/>')
    with open(args.arch_xml, "w") as f:
        f.write('<?xml version="1.0"?>\n<module>\n'
                f'   <function symbol="{args.kernel_name}" name="{args.kernel_name}">\n'
                '      <bundles>\n' + "\n".join(bundles) + '\n      </bundles>\n'
                '      <parameters>\n' + "\n".join(parms) + '\n      </parameters>\n'
                '   </function>\n</module>\n')
    print(f"wrote {args.arch_xml}")


def main():
    args = parse_args()
    with open(args.testbench) as f:
        src = f.read()

    params = sorted((int(idx), ctype.strip(), body.count(",") + 1)
                    for ctype, idx, body in ARRAY_RE.findall(src))
    if not params:
        sys.exit(f"ERROR: no P<i>_temp[] argument arrays found in {args.testbench}")
    if [p[0] for p in params] != list(range(len(params))):
        sys.exit(f"ERROR: argument arrays in {args.testbench} are not P0..P{len(params) - 1}")

    outputs = {len(params) - 1} if args.outputs is None else {int(i) for i in args.outputs.split(",")}
    random.seed(args.seed)

    values = []
    for idx, ctype, count in params:
        is_int = ctype.split()[-1] in INT_TYPES
        if idx in outputs:
            vals = [0 if is_int else 0.0] * count
        elif is_int:
            vals = [random.randint(int(args.low), int(args.high)) for _ in range(count)]
        else:
            vals = [round(random.uniform(args.low, args.high), args.decimals) for _ in range(count)]
        values.append(vals)

    attrs = []
    for (idx, _, _), vals in zip(params, values):
        attrs.append(f'{args.param_prefix}{idx + args.param_base}="{{{",".join(str(v) for v in vals)}}}"')
    if args.expected_from:
        for idx, vals in sorted(run_on_host(args, params, values, outputs).items()):
            attrs.append(f'{args.param_prefix}{idx + args.param_base}:output="{format_values(vals)}"')

    with open(args.output, "w") as f:
        f.write('<?xml version="1.0"?>\n<function>\n   <testbench ' + " ".join(attrs) + "/>\n</function>\n")

    if args.arch_xml:
        write_arch_xml(args, params)

    summary = ", ".join(f"{args.param_prefix}{i + args.param_base}:{t}[{n}]{'(out)' if i in outputs else ''}"
                        for i, t, n in params)
    print(f"wrote {args.output} (seed={args.seed}): {summary}")


if __name__ == "__main__":
    main()
