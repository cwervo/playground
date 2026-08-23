"""Edge-preserving filters used to stabilise a very noisy, very dark frame."""

from __future__ import annotations

import numpy as np
from scipy import ndimage


def box(a: np.ndarray, r: int) -> np.ndarray:
    return ndimage.uniform_filter(a, size=2 * r + 1, mode="nearest")


def guided_filter(guide: np.ndarray, src: np.ndarray, r: int = 4,
                  eps: float = 1e-3) -> np.ndarray:
    """He, Sun & Tang guided filter.

    Smooths `src` while borrowing edges from `guide`. Used to denoise the
    chromaticity channels using luminance structure: in this photograph the
    hand's chroma is nearly pure shot noise, but its luminance edges are intact,
    so the guide carries the geometry and the output keeps finger boundaries
    that a plain blur would dissolve.
    """
    mean_g = box(guide, r)
    mean_s = box(src, r)
    cov = box(guide * src, r) - mean_g * mean_s
    var = box(guide * guide, r) - mean_g * mean_g
    a = cov / (var + eps)
    b = mean_s - a * mean_g
    return box(a, r) * guide + box(b, r)


def local_detail(a: np.ndarray, r: int = 3) -> np.ndarray:
    """Local high-frequency energy: RMS deviation from a box mean.

    Doubles as a focus measure. The hand is the nearest object in the frame and
    is motion-blurred and defocused, so it is markedly *smoother* than the
    in-focus bookshelf behind it -- which makes this one of the few features
    that separates hand from background when both are nearly black.
    """
    m = box(a, r)
    return np.sqrt(np.maximum(box(a * a, r) - m * m, 0.0))


def unsharp(a: np.ndarray, sigma: float = 3.0, amount: float = 1.0) -> np.ndarray:
    return a + amount * (a - ndimage.gaussian_filter(a, sigma, mode="nearest"))
