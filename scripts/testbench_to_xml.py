#!/usr/bin/env python3
"""Build a bambu XML test vector from soda-opt's generated C testbench.

soda-opt's -soda-extract-arguments-to-c-testbench writes a
forward_kernel_testbench.c that declares one `<type> P<i>_temp[] = {...};`
array per kernel argument, in call order. This reads those declarations for
each argument's element type and length, and emits a bambu XML test vector
(the `--generate-tb=<file.xml>` input of bambu's self-contained, non-DPI
testbench) with random values for the inputs and zeros for the outputs.

The XML attribute names are the kernel's parameter names as bambu sees
them. For C produced by ll_to_c_cbe.sh (llvm-cbe) those are _1.._N.

Usage:
    testbench_to_xml.py forward_kernel_testbench.c -o test.xml
    testbench_to_xml.py forward_kernel_testbench.c -o test.xml --outputs 3,4 --seed 7
"""

import argparse
import random
import re
import sys

ARRAY_RE = re.compile(r"\b([A-Za-z_][\w ]*?)\s+P(\d+)_temp\[\]\s*=\s*\{([^}]*)\}")
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
    parser.add_argument("--seed", type=int, default=42, help="random.seed() value, for reproducible vectors")
    parser.add_argument("--low", type=float, default=1.0, help="Lower bound for generated values")
    parser.add_argument("--high", type=float, default=5.0, help="Upper bound for generated values")
    parser.add_argument("--decimals", type=int, default=3, help="Decimal places for floating-point values")
    return parser.parse_args()


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

    attrs = []
    for idx, ctype, count in params:
        is_int = ctype.split()[-1] in INT_TYPES
        if idx in outputs:
            vals = [0 if is_int else 0.0] * count
        elif is_int:
            vals = [random.randint(int(args.low), int(args.high)) for _ in range(count)]
        else:
            vals = [round(random.uniform(args.low, args.high), args.decimals) for _ in range(count)]
        name = f"{args.param_prefix}{idx + args.param_base}"
        attrs.append(f'{name}="{{{",".join(str(v) for v in vals)}}}"')

    with open(args.output, "w") as f:
        f.write('<?xml version="1.0"?>\n<function>\n   <testbench ' + " ".join(attrs) + "/>\n</function>\n")

    summary = ", ".join(f"{args.param_prefix}{i + args.param_base}:{t}[{n}]{'(out)' if i in outputs else ''}"
                        for i, t, n in params)
    print(f"wrote {args.output} (seed={args.seed}): {summary}")


if __name__ == "__main__":
    main()
