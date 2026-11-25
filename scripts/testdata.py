"""Reads a testdata.h: a kernel's inputs, the results the framework computes from them, the tolerance,
the order the outlined forward_kernel takes its parameters in, and the names of @forward's parameters
and results. torchscript.py --emit-testdata writes it for a PyTorch kernel (sb_cli experiments; the
Makefile rule is in scripts/mkinc/ll_to_binary.mk), with PolyBench's init_array as the inputs, and
scripts/tf_testdata.py for a TensorFlow model (TD_FRAMEWORK "tensorflow"). With one result the buffers are td_out and td_golden, with
several they are numbered (td_out0, td_golden0, ...)."""
import re


class TestData:
    def __init__(self, path):
        text = open(path).read()
        self.ctype = re.search(r"typedef (\w+) td_elem_t;", text).group(1)
        self.tol = float(re.search(r"#define TD_TOL\s+(\S+)", text).group(1))
        self.kernel = re.search(r'#define TD_KERNEL\s+"(\w+)"', text).group(1)
        m = re.search(r"#define TD_NOUT\s+(\d+)", text)
        nout = int(m.group(1)) if m else 1
        numbered = "td_out0" in text

        def array(name):
            m = re.search(rf"td_elem_t {name}\[(\d+)\](?: = \{{(.*?)\}})?;", text, re.S)
            n = int(m.group(1))
            vals = [float(v) for v in m.group(2).replace("\n", " ").split(",") if v.strip()] if m.group(2) else [0.0] * n
            assert len(vals) == n, name
            return vals

        # parameters of @forward, in signature order, then the results
        self.inputs = []
        while re.search(rf"td_elem_t td_p{len(self.inputs)}\[", text):
            self.inputs.append(array(f"td_p{len(self.inputs)}"))
        self.golden = [array(f"td_golden{k}" if numbered else "td_golden") for k in range(nout)]
        call = re.search(r"#define TD_CALL\(F\) F\(([^)]*)\)", text).group(1)
        # the call order: ("in", i) or ("out", k)
        self.call = []
        for a in call.split(","):
            a = a.strip()
            if a.startswith("td_out"):
                self.call.append(("out", int(a[6:] or 0)))
            else:
                self.call.append(("in", int(a[4:])))
        assert sorted(i for t, i in self.call if t == "in") == list(range(len(self.inputs)))
        assert sorted(k for t, k in self.call if t == "out") == list(range(nout))
        self.nbytes = 4 if self.ctype == "float" else 8
        self.dataset = re.search(r'#define TD_DATASET\s+"(\w+)"', text).group(1)
        # shapes from the comments: "/* parameter 0: shape 38x42 */", "/* result: shape 42 */"
        self.in_shapes = [re.search(rf"/\* parameter {i}: shape (\S+) \*/", text).group(1)
                          for i in range(len(self.inputs))]
        self.out_shapes = [re.search(r"/\* result(?: %d)?: shape (\S+) \*/" % k, text).group(1)
                           for k in range(nout)]
        self.dtype = re.search(r'#define TD_DTYPE\s+"(\w+)"', text).group(1)
        # @forward's input names (absent from headers written before TD_PARAM_NAMES)
        m = re.search(r'#define TD_PARAM_NAMES\s+"([^"]*)"', text)
        names = m.group(1).split() if m else []
        self.param_names = names if len(names) == len(self.inputs) else [f"p{i}" for i in range(len(self.inputs))]
        # the framework that computed the results (headers without TD_FRAMEWORK are torchscript.py's)
        m = re.search(r'#define TD_FRAMEWORK\s+"(\w+)"', text)
        self.framework = m.group(1) if m else "pytorch"
        # the results' names, where the framework has them (TD_RESULT_NAMES)
        m = re.search(r'#define TD_RESULT_NAMES\s+"([^"]*)"', text)
        names = m.group(1).split() if m else []
        self.result_names = names if len(names) == nout else (["out"] if nout == 1 else [f"out{k}" for k in range(nout)])

    def call_arrays(self):
        """The kernel's arguments in the order forward_kernel takes them (results start at zero)."""
        return [self.inputs[i] if t == "in" else [0.0] * len(self.golden[i]) for t, i in self.call]

    def out_positions(self):
        """Position in the call of each result: result k is argument out_positions()[k]."""
        pos = {k: j for j, (t, k) in enumerate(self.call) if t == "out"}
        return [pos[k] for k in range(len(self.golden))]
