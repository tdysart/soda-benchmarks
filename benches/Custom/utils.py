"""Helpers for the kernels under Custom/: the dataset table, and the rest from the PolyBench helpers."""

from benches.PolyBenchPyTorch.linear_algebra.utils import generate_mlir, resolve_dtype

__all__ = ["generate_mlir", "get_dataset_dimensions", "resolve_dtype"]

_DATASETS: dict[str, dict[str, dict[str, int]]] = {
    "vadd_relu": {
        "TEST": {"n": 8},
        "MINI": {"n": 64},
        "SMALL": {"n": 512},
    },
}


def get_dataset_dimensions(kernel: str, dataset: str) -> dict[str, int]:
    """Dimension dict for a Custom kernel and dataset size (TEST, MINI, SMALL)."""
    if kernel not in _DATASETS:
        raise ValueError(f"Unknown kernel: '{kernel}'. Known kernels: {sorted(_DATASETS)}")
    dataset = dataset.upper()
    if dataset not in _DATASETS[kernel]:
        raise ValueError(f"Unknown dataset: '{dataset}'. Choose from {sorted(_DATASETS[kernel])}")
    return _DATASETS[kernel][dataset]
