#!/usr/bin/env python3
"""vadd_relu: out = relu(a + b), the smallest kernel that is not a PolyBench one.

A vector add followed by a rectifier (max(0, x)): an elementwise kernel with a comparison and a select, which
no PolyBench kernel has.
"""

import torch
import torch.nn as nn


class VaddRelu(nn.Module):
    """out = relu(a + b) for vectors of length n."""

    def __init__(self, n: int) -> None:
        super().__init__()
        self.n = n

    def forward(self, a: torch.Tensor, b: torch.Tensor) -> torch.Tensor:
        return torch.relu(a + b)


def init_array(n: int, dtype: torch.dtype = torch.float32) -> tuple[torch.Tensor, torch.Tensor]:
    """Deterministic inputs in [-0.5, 0.5), so some sums are negative. Returns (a, b)."""
    a = torch.zeros(n, dtype=dtype)
    b = torch.zeros(n, dtype=dtype)
    for i in range(n):
        a[i] = ((i * 7) % n) / float(n) - 0.5
        b[i] = ((i * 3 + 1) % n) / float(n) - 0.5
    return a, b
