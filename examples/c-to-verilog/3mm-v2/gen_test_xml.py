#!/usr/bin/env python3
"""Generate a bambu XML test vector for the forward_kernel (3mm) example.

forward_kernel computes G = (A*B) * (C*D), where A/B/C/D are S x S float
matrices. The XML attribute names (P0..P6) are the pragma-renamed formal
parameter names bambu sees after preprocessing, not the source-level names
(E/A/B/F/C/D/G) -- see documentation/install/install_macos.doc in panda-bambu
for details.

Usage:
    ./gen_test_xml.py -o test.xml --seed 42
    ./gen_test_xml.py -o test_wide_range.xml --seed 7 --low -100 --high 100
"""

import argparse
import random


def arr(vals):
    return "{" + ",".join(str(v) for v in vals) + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--output", required=True, help="Path to write the generated XML test vector")
    parser.add_argument("-s", "--size", type=int, default=10, help="Matrix dimension S (default: 10, matching forward_kernel.c)")
    parser.add_argument("--seed", type=int, default=42, help="random.seed() value, for reproducible test vectors")
    parser.add_argument("--low", type=float, default=1.0, help="Lower bound for generated matrix values")
    parser.add_argument("--high", type=float, default=5.0, help="Upper bound for generated matrix values")
    parser.add_argument("--decimals", type=int, default=3, help="Decimal places to round generated values to")
    args = parser.parse_args()

    random.seed(args.seed)
    n = args.size * args.size

    def random_matrix():
        return [round(random.uniform(args.low, args.high), args.decimals) for _ in range(n)]

    a = random_matrix()
    b = random_matrix()
    c = random_matrix()
    d = random_matrix()
    zeros = [0.0] * n

    # Attribute names are the pragma-renamed formal parameter names (P0..P6),
    # not the source-level names (E/A/B/F/C/D/G) -- bambu only sees the
    # expanded names by the time it parses the test vector.
    # P0=E (output, zeros), P1=A, P2=B, P3=F (output, zeros),
    # P4=C, P5=D, P6=G (output, zeros)
    xml = f'''<?xml version="1.0"?>
<function>
   <testbench P0="{arr(zeros)}" P1="{arr(a)}" P2="{arr(b)}" P3="{arr(zeros)}" P4="{arr(c)}" P5="{arr(d)}" P6="{arr(zeros)}"/>
</function>
'''

    with open(args.output, "w") as f:
        f.write(xml)

    print(f"wrote {args.output} (S={args.size}, seed={args.seed}, range=[{args.low},{args.high}])")


if __name__ == "__main__":
    main()
