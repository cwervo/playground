"""Adaptive quadtree tiling with overlapping halos and feathered reassembly.

The image is split recursively wherever local detail is high, so flat wall gets
a few big tiles and the fingers get many small ones. Each leaf is then grown by
a halo so neighbouring tiles overlap; every per-tile estimate is therefore
supported by several independent fits, and they are recombined with a raised-
cosine partition of unity so no tile seam survives into the output.

This is what makes the piecemeal processing safe: a per-tile statistic (a dark-
object offset, a contrast stretch, a mixture fit) is allowed to vary spatially,
but it varies smoothly because overlapping tiles disagree only gradually.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterator

import numpy as np
from scipy import ndimage


@dataclass(frozen=True)
class Tile:
    """One quadtree leaf: `core` is its exclusive territory, `halo` the region
    it actually reads and writes."""
    y0: int
    x0: int
    y1: int
    x1: int
    hy0: int
    hx0: int
    hy1: int
    hx1: int
    depth: int

    @property
    def core(self):
        return slice(self.y0, self.y1), slice(self.x0, self.x1)

    @property
    def halo(self):
        return slice(self.hy0, self.hy1), slice(self.hx0, self.hx1)

    @property
    def halo_shape(self):
        return self.hy1 - self.hy0, self.hx1 - self.hx0

    def __repr__(self):
        return (f"Tile(d={self.depth} core=[{self.y0}:{self.y1},"
                f"{self.x0}:{self.x1}] halo={self.halo_shape})")


def _detail(a: np.ndarray, q: float = 95.0, max_samples: int = 4096) -> float:
    """Detail energy: a high quantile of the 4-neighbour Laplacian magnitude.

    A quantile rather than a variance so a handful of hot pixels cannot force a
    split, and a *high* quantile rather than a MAD so that structure occupying a
    small fraction of a large tile still counts -- which is the case that
    matters, since a finger crossing one corner of a wall tile must subdivide it.
    Large tiles are strided down before the quantile; the estimate only needs to
    be good enough to compare against one threshold.
    """
    if a.shape[0] < 3 or a.shape[1] < 3:
        return 0.0
    step = max(1, int(np.sqrt(a.size / max_samples)))
    b = a[::step, ::step]
    if b.shape[0] < 3 or b.shape[1] < 3:
        b = a
    lap = (4 * b[1:-1, 1:-1] - b[:-2, 1:-1] - b[2:, 1:-1]
           - b[1:-1, :-2] - b[1:-1, 2:])
    return float(np.percentile(np.abs(lap), q))


def build(guide: np.ndarray, min_size: int = 24, max_depth: int = 6,
          detail_thresh: float = 0.006, overlap: float = 0.35,
          presmooth: float = 1.5) -> list[Tile]:
    """Build the overlapping quadtree over a single-channel guide image.

    guide          the field whose structure drives subdivision (here L*/100)
    min_size       a leaf is never split below this many pixels on a side
    max_depth      hard recursion cap
    detail_thresh  split while the leaf's Laplacian quantile exceeds this
    overlap        halo margin as a fraction of the leaf's side length
    presmooth      Gaussian sigma applied to the guide before measuring detail

    `presmooth` is not cosmetic. CIELAB L* is a cube-root of luminance, so its
    slope diverges as luminance goes to zero and shot noise in deep shadow is
    amplified far more than the same noise in the highlights. Measured on this
    photograph, the near-black defocused hand scored a *higher* Laplacian
    quantile (0.180) than the in-focus bookshelf behind it (0.108) purely from
    that amplification. Without presmoothing the tree subdivides hardest
    exactly where there is least information. A modest blur restores the
    intended ordering: the criterion then tracks structure, not sensor noise.
    """
    if presmooth > 0:
        guide = ndimage.gaussian_filter(guide, presmooth, mode="nearest")
    h, w = guide.shape
    tiles: list[Tile] = []

    def recurse(y0, x0, y1, x1, depth):
        hh, ww = y1 - y0, x1 - x0
        splittable = (depth < max_depth and hh >= 2 * min_size
                      and ww >= 2 * min_size)
        if splittable and _detail(guide[y0:y1, x0:x1]) > detail_thresh:
            ym, xm = y0 + hh // 2, x0 + ww // 2
            recurse(y0, x0, ym, xm, depth + 1)
            recurse(y0, xm, ym, x1, depth + 1)
            recurse(ym, x0, y1, xm, depth + 1)
            recurse(ym, xm, y1, x1, depth + 1)
            return
        my, mx = int(round(hh * overlap)), int(round(ww * overlap))
        tiles.append(Tile(y0, x0, y1, x1,
                          max(0, y0 - my), max(0, x0 - mx),
                          min(h, y1 + my), min(w, x1 + mx), depth))

    recurse(0, 0, h, w, 0)
    return tiles


def feather(tile: Tile) -> np.ndarray:
    """Raised-cosine blend weight over a tile's halo.

    Unity across the core, tapering to (almost) zero at the halo edge. A small
    floor keeps the normalising sum strictly positive everywhere.
    """
    def ramp(n, lo_pad, hi_pad):
        w = np.ones(n)
        if lo_pad > 0:
            t = (np.arange(lo_pad) + 0.5) / lo_pad
            w[:lo_pad] = 0.5 * (1 - np.cos(np.pi * t))
        if hi_pad > 0:
            t = (np.arange(hi_pad) + 0.5) / hi_pad
            w[n - hi_pad:] = 0.5 * (1 + np.cos(np.pi * t))
        return w

    hy, hx = tile.halo_shape
    wy = ramp(hy, tile.y0 - tile.hy0, tile.hy1 - tile.y1)
    wx = ramp(hx, tile.x0 - tile.hx0, tile.hx1 - tile.x1)
    return np.outer(wy, wx) + 1e-4


class Mosaic:
    """Weighted accumulator that fuses per-tile results back into one image."""

    def __init__(self, shape, n_channels: int | None = None):
        self.shape = shape
        self.n_channels = n_channels
        acc_shape = shape if n_channels is None else (*shape, n_channels)
        self._acc = np.zeros(acc_shape, dtype=np.float64)
        self._wsum = np.zeros(shape, dtype=np.float64)

    def add(self, tile: Tile, value: np.ndarray, weight: np.ndarray | None = None):
        w = feather(tile) if weight is None else weight
        sl = tile.halo
        if self.n_channels is None:
            self._acc[sl] += value * w
        else:
            self._acc[sl] += value * w[..., None]
        self._wsum[sl] += w

    def result(self) -> np.ndarray:
        w = np.maximum(self._wsum, 1e-12)
        return self._acc / (w if self.n_channels is None else w[..., None])

    @property
    def coverage(self) -> np.ndarray:
        return self._wsum


def process(field: np.ndarray, tiles: list[Tile],
            fn: Callable[[np.ndarray, Tile], np.ndarray],
            n_channels: int | None = None) -> np.ndarray:
    """Run `fn` on every tile's halo view and feather-blend the results."""
    mosaic = Mosaic(field.shape[:2], n_channels)
    for t in tiles:
        mosaic.add(t, fn(field[t.halo], t))
    return mosaic.result()


def iter_tiles(tiles: list[Tile]) -> Iterator[Tile]:
    """Leaves ordered coarse-to-fine, which keeps overlays legible."""
    return iter(sorted(tiles, key=lambda t: t.depth))


def stats(tiles: list[Tile], shape) -> dict:
    depths = np.array([t.depth for t in tiles])
    areas = np.array([(t.y1 - t.y0) * (t.x1 - t.x0) for t in tiles])
    halo_areas = np.array([np.prod(t.halo_shape) for t in tiles])
    return {
        "n_leaves": len(tiles),
        "depth_min": int(depths.min()),
        "depth_max": int(depths.max()),
        "leaf_px_min": int(areas.min()),
        "leaf_px_max": int(areas.max()),
        "core_coverage": float(areas.sum() / (shape[0] * shape[1])),
        "mean_overlap_factor": float(halo_areas.sum() / areas.sum()),
    }
