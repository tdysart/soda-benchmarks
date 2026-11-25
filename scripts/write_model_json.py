#!/usr/bin/env python3
"""Write model.json: the description of a kernel that a model consumer (soda-sst-system) reads.

    scripts/write_model_json.py <bambu_dir> <testdata.h>

<bambu_dir> is the output of bambu's pure-Verilog testbench (bambu-devpanda-tb/<flow>/: the
Verilog, tb_init.mem, tb_expected.mem, 07_results.txt, bambu-log), and <testdata.h> the test data
the testbench was made from (scripts/gen_bambu_tb.py). model.json goes into <bambu_dir>, beside
the files it lists, and holds

  * the kernel's parameters in the order the kernel takes them, with their names, shapes, element
    type and place in @forward's signature (from testdata.h);
  * the reference: the framework's results (PyTorch, TensorFlow) against what bambu's native run of
    the kernel left
    (scripts/check_golden.py). A consumer refuses a model whose reference did not pass;
  * the interface: the top module, the Verilog files, bambu's version and settings as bambu-log
    records them, and the testbench's files.

The format is soda-sst-system's docs/ModelFormat.md. The file is written whether the reference
passes or not, so the verdict can be read; the exit status is 1 if it does not.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_golden import compare
from testdata import TestData

FORMAT = 1
BAMBU_DEFAULT_BASE = 0x40000000  # bambu's OPT_base_address when --base-address is not given


def bambu_run(bambu_dir):
    """bambu's version and the options it was run with, from its log."""
    log = open(os.path.join(bambu_dir, "bambu-log"), errors="replace").read()
    version = re.search(r"^Version: (.*)$", log, re.M)
    cmd = re.search(r"Bambu executed with: (.*)$", log, re.M)
    opts = {}
    for tok in re.findall(r"'([^']*)'", cmd.group(1) if cmd else ""):
        if tok.startswith("--") and "=" in tok:
            k, v = tok[2:].split("=", 1)
            opts[k] = v
    return (version.group(1).strip() if version else "unknown"), opts


def source_commit():
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        commit = subprocess.run(["git", "-C", here, "rev-parse", "--short", "HEAD"],
                                capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", here, "status", "--porcelain", "--untracked-files=no"],
                               capture_output=True, text=True, check=True).stdout.strip()
        return commit + (" (with uncommitted changes)" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def shape(text):
    return [] if text == "scalar" else [int(d) for d in text.split("x")]


def main():
    bambu_dir, tdpath = sys.argv[1], sys.argv[2]
    td = TestData(tdpath)
    version, opts = bambu_run(bambu_dir)
    top = opts.get("top-fname", "forward_kernel")

    n_in, n_out = len(td.inputs), len(td.golden)
    out_names = td.result_names
    parameters = []
    for kind, i in td.call:  # the kernel's own order: P0, P1, ...
        if kind == "in":
            parameters.append({"name": td.param_names[i], "role": "input", "type": td.dtype,
                               "shape": shape(td.in_shapes[i]), "position": i})
        else:
            parameters.append({"name": out_names[i], "role": "output", "type": td.dtype,
                               "shape": shape(td.out_shapes[i]), "position": n_in + i})

    ref = compare(bambu_dir, td)
    verilog = ["panda_libtech.v", f"{top}.v"]
    for f in verilog + ["tb_init.mem", "tb_expected.mem", "07_results.txt"]:
        if not os.path.isfile(os.path.join(bambu_dir, f)):
            sys.exit(f"write_model_json.py: {bambu_dir}/{f} is missing")

    base = opts.get("base-address")
    model = {
        "format": FORMAT,
        "name": td.kernel,
        "source": {
            "repository": "soda-benchmarks",
            "commit": source_commit(),
            "framework": td.framework,
            "dataset": td.dataset,
        },
        "parameters": parameters,
        "reference": {
            "kind": td.framework,
            "passed": ref["passed"],
            "largest_error": ref["largest_error"],
            "tolerance": ref["tolerance"],
            "elements": ref["elements"],
        },
        "interface": {
            "kind": "bambu-native",
            "top": top,
            "verilog": verilog,
            "clock_port": "clock",
            "bambu": {
                "version": version,
                "channels": int(opts.get("channels-number", 1)),
                "memory_policy": opts.get("memory-allocation-policy", "unknown"),
                "device": opts.get("device", "unknown"),
                "clock_period_ns": float(opts["clock-period"]) if "clock-period" in opts else None,
                "base_address": hex(int(base, 0) if base else BAMBU_DEFAULT_BASE),
                "testbench": {"init": "tb_init.mem", "expected": "tb_expected.mem", "cycles": "07_results.txt"},
            },
        },
    }
    out = os.path.join(bambu_dir, "model.json")
    with open(out, "w") as f:
        json.dump(model, f, indent=1)
        f.write("\n")
    verdict = "passed" if ref["passed"] else f"FAILED ({ref['out_of_tolerance']} elements out of tolerance)"
    print(f"{out}: {td.kernel}, {len(parameters)} parameters, reference {verdict}, "
          f"largest error {ref['largest_error']:.3g}")
    sys.exit(0 if ref["passed"] else 1)


if __name__ == "__main__":
    main()
