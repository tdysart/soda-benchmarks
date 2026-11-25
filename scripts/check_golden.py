#!/usr/bin/env python3
"""Compare what bambu's native run of the kernel's IR left with the result the framework computes.

    scripts/check_golden.py <bambu_dir> <testdata.h>

bambu's testbench (scripts/gen_bambu_tb.py) runs the lowered kernel natively on the real inputs and
records the memory it leaves in tb_expected.mem; the Verilog, in Verilator and in SST, is checked
against that. This closes the chain to the framework (PyTorch, TensorFlow): the result buffer in
tb_expected.mem must match the framework's golden result on the same inputs, element by element,
within the tolerance testdata.h gives (relative for results above 1). Exit status 1 if not.
"""
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from testdata import TestData


def read_regions(path):
    params, mem = {}, {}
    for line in open(path):
        t = line.split()
        if not t:
            continue
        if t[0] == "w":
            params[int(t[2])] = int(t[4], 16)
        elif t[0] == "m":
            addr, hexs = int(t[3], 16), t[5]
            for i, b in enumerate(bytes.fromhex(hexs)[::-1]):
                mem[addr + i] = b
    return params, mem


def compare(bambu_dir, td):
    """The framework's results against tb_expected.mem: a dict with passed, largest_error, tolerance,
    elements, out_of_tolerance and first (the first element out of tolerance, or None)."""
    params, _ = read_regions(f"{bambu_dir}/tb_init.mem")
    _, expected = read_regions(f"{bambu_dir}/tb_expected.mem")
    w = td.nbytes
    worst, bad, total, first = 0.0, 0, 0, None
    for k, (pos, golden) in enumerate(zip(td.out_positions(), td.golden)):
        n, base = len(golden), params[pos]
        raw = bytes(expected.get(base + i, 0) for i in range(n * w))
        got = struct.unpack(f"<{n}{'f' if w == 4 else 'd'}", raw)
        total += n
        for i, (g, ref) in enumerate(zip(got, golden)):
            err = abs(g - ref) / max(1.0, abs(ref))
            worst = max(worst, err)
            if not err <= td.tol:  # also catches nan
                bad += 1
                first = first or (k, i, g, ref)
    return {"passed": bad == 0, "largest_error": worst, "tolerance": td.tol, "elements": total,
            "out_of_tolerance": bad, "first": first}


def main():
    bambu_dir, tdpath = sys.argv[1], sys.argv[2]
    td = TestData(tdpath)
    r = compare(bambu_dir, td)
    worst, bad, total, first = r["largest_error"], r["out_of_tolerance"], r["elements"], r["first"]
    verdict = "OK" if bad == 0 else "MISMATCH"
    framework = {"pytorch": "PyTorch", "tensorflow": "TensorFlow"}.get(td.framework, td.framework)
    print(f"{framework} golden vs bambu's native run of the IR, {td.kernel}: {verdict}: {total} elements "
          f"in {len(td.golden)} result(s), largest error {worst:.3g} (tolerance {td.tol:g}), {bad} out of tolerance"
          + (f"; first: result {first[0]} element {first[1]} got {first[2]!r} expected {first[3]!r}" if first else ""))
    sys.exit(0 if bad == 0 else 1)


if __name__ == "__main__":
    main()
