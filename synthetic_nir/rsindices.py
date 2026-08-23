"""Remote-sensing band math applied to the synthetic NIR stack.

The three simulated vein-finder bands are treated exactly like a three-band
satellite scene: haze/path-radiance is removed per tile by dark-object
subtraction, normalised-difference indices isolate the chromophore of interest,
a tasseled-cap style rotation gives interpretable orthogonal axes, and a
minimum-noise-fraction transform separates signal from the sensor noise that
dominates this very underexposed frame.
"""

from __future__ import annotations

import numpy as np

from .quadtree import Mosaic, Tile


# --- per-tile radiometric correction ----------------------------------------

def dark_object_subtract(band: np.ndarray, tiles: list[Tile],
                         percentile: float = 1.0,
                         floor_frac: float = 0.02) -> np.ndarray:
    """Dark-object subtraction, computed per quadtree leaf.

    In satellite work DOS removes additive atmospheric path radiance by
    assuming the darkest pixel in a scene is truly black. Here the additive
    term is veiling glare plus sensor black-offset, and it varies across the
    frame because half of it is lit window and half is deep shadow -- so the
    offset is estimated per leaf and feather-blended, which turns a global
    constant into a smooth field.
    """
    mos = Mosaic(band.shape)
    for t in tiles:
        sub = band[t.halo]
        offset = np.percentile(sub, percentile)
        # Never subtract so much that the tile collapses to zero.
        offset = min(offset, float(np.mean(sub)) * (1.0 - floor_frac))
        mos.add(t, np.full(t.halo_shape, offset))
    from scipy import ndimage as _nd
    sigma = max(4.0, 0.05 * min(band.shape))
    return band - _nd.gaussian_filter(mos.result(), sigma, mode="nearest")


def percentile_stretch(band: np.ndarray, tiles: list[Tile] | None = None,
                       lo: float = 2.0, hi: float = 98.0,
                       mask: np.ndarray | None = None) -> np.ndarray:
    """Linear contrast stretch between two percentiles.

    With `tiles`, the endpoints are estimated per leaf and blended, which is the
    adaptive-stretch equivalent of a per-scene stretch and is what makes the
    shadowed hand legible at all.
    """
    if tiles is None:
        ref = band[mask] if mask is not None and mask.any() else band
        a, b = np.percentile(ref, [lo, hi])
        return np.clip((band - a) / max(b - a, 1e-9), 0.0, 1.0)

    lo_m, hi_m = Mosaic(band.shape), Mosaic(band.shape)
    for t in tiles:
        sub = band[t.halo]
        ref = sub
        if mask is not None:
            m = mask[t.halo]
            if m.sum() > 0.10 * m.size:
                ref = sub[m]
        a, b = np.percentile(ref, [lo, hi])
        lo_m.add(t, np.full(t.halo_shape, a))
        hi_m.add(t, np.full(t.halo_shape, b))
    a, b = lo_m.result(), hi_m.result()
    # The fused endpoint fields are still piecewise-ish: neighbouring leaves at
    # different depths pick quite different percentiles and the feather only
    # spans each halo, so steps survive as visible tile blocks. Smoothing the
    # endpoints (not the image) removes the blocking while keeping the stretch
    # locally adaptive -- the endpoints are meant to be a slowly varying field.
    from scipy import ndimage as _nd
    sigma = max(4.0, 0.05 * min(band.shape))
    a = _nd.gaussian_filter(a, sigma, mode="nearest")
    b = _nd.gaussian_filter(b, sigma, mode="nearest")
    return np.clip((band - a) / np.maximum(b - a, 1e-9), 0.0, 1.0)


# --- band indices ------------------------------------------------------------

def normalized_difference(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """(a - b) / (a + b), the NDVI form."""
    return (a - b) / np.maximum(a + b, 1e-9)


def ndvi_vein(b760: np.ndarray, b850: np.ndarray) -> np.ndarray:
    """Normalised Difference Vein Index.

    Deoxygenated haemoglobin absorbs ~4x more at 760 nm than oxygenated, while
    at 850 nm the ordering reverses. Venous blood therefore darkens 760 while
    leaving 850 comparatively bright, and NDVI rises. This is structurally the
    same trick as vegetation NDVI: one band where the target absorbs, one where
    it does not.
    """
    return normalized_difference(b850, b760)


def ndwi_tissue(b850: np.ndarray, b940: np.ndarray) -> np.ndarray:
    """Tissue-water index; 940 nm sits on a water absorption band."""
    return normalized_difference(b850, b940)


def simple_ratio(b760: np.ndarray, b850: np.ndarray) -> np.ndarray:
    return b850 / np.maximum(b760, 1e-9)


def mavi(b760: np.ndarray, b850: np.ndarray, L: float = 0.5) -> np.ndarray:
    """Melanin-Adjusted Vein Index, built on the SAVI form.

    SAVI adds a soil-brightness constant L to damp the background's influence on
    NDVI. Melanin plays the soil's role here: it is a broadband multiplicative
    background that shifts both bands together, and the same correction damps
    it.
    """
    return (1.0 + L) * (b850 - b760) / np.maximum(b850 + b760 + L, 1e-9)


# --- multivariate transforms -------------------------------------------------

def _stack(bands: dict) -> tuple:
    keys = sorted(bands)
    return np.stack([bands[k] for k in keys], axis=-1), keys


def tasseled_cap(bands: dict, mask: np.ndarray | None = None) -> tuple:
    """Gram-Schmidt tasseled-cap rotation into interpretable axes.

    Axis 1 (Brightness)  the scene's mean spectral direction: overall albedo,
                         which is mostly melanin and illumination.
    Axis 2 (Vascularity) the 850-vs-760 contrast, orthogonalised against
                         brightness so it cannot be faked by exposure.
    Axis 3 (Hydration)   the 940 water axis, orthogonal to both.
    """
    x, keys = _stack(bands)
    d = x.shape[-1]
    flat = x.reshape(-1, d)
    ref = flat[mask.ravel()] if mask is not None and mask.any() else flat

    u1 = ref.mean(axis=0)
    u1 /= np.linalg.norm(u1)
    seeds = np.array([[-1.0, 1.0, 0.0], [0.0, -1.0, 1.0]])[:, :d]
    basis = [u1]
    for s in seeds:
        v = s.astype(float)
        for b in basis:
            v -= (v @ b) * b
        nv = np.linalg.norm(v)
        if nv > 1e-8:
            basis.append(v / nv)
    R = np.stack(basis)
    proj = (flat - ref.mean(axis=0)) @ R.T
    names = ["Brightness", "Vascularity", "Hydration"][:R.shape[0]]
    return {n: proj[:, i].reshape(x.shape[:-1]) for i, n in enumerate(names)}, R, keys


def mnf(bands: dict, mask: np.ndarray | None = None) -> tuple:
    """Minimum Noise Fraction transform.

    Ordinary PCA maximises variance, which in a badly underexposed frame means
    it happily rank-orders the noise. MNF first estimates the noise covariance
    from nearest-neighbour differences, whitens by it, and only then runs PCA --
    so components come out ordered by signal-to-noise rather than by raw
    variance. That ordering is the useful part here.
    """
    x, keys = _stack(bands)
    h, w, d = x.shape
    flat = x.reshape(-1, d)

    dh = (x[:, 1:, :] - x[:, :-1, :]).reshape(-1, d)
    dv = (x[1:, :, :] - x[:-1, :, :]).reshape(-1, d)
    noise = np.concatenate([dh, dv], axis=0) / np.sqrt(2.0)
    cov_n = np.cov(noise.T) + np.eye(d) * 1e-12

    ev, evec = np.linalg.eigh(cov_n)
    whiten = evec @ np.diag(1.0 / np.sqrt(np.maximum(ev, 1e-15))) @ evec.T

    ref = flat[mask.ravel()] if mask is not None and mask.any() else flat
    mu = ref.mean(axis=0)
    xw = (flat - mu) @ whiten
    refw = (ref - mu) @ whiten
    cov_s = np.cov(refw.T)
    ev2, evec2 = np.linalg.eigh(cov_s)
    order = np.argsort(ev2)[::-1]
    evec2, ev2 = evec2[:, order], ev2[order]

    comps = (xw @ evec2).reshape(h, w, d)
    snr = ev2  # eigenvalues of the noise-whitened signal covariance
    return {f"MNF{i + 1}": comps[..., i] for i in range(d)}, snr, keys


def false_color(b760, b850, b940, tiles=None, mask=None) -> np.ndarray:
    """Standard false-colour composite: longest band to red, shortest to blue.

    Matches the convention of a colour-infrared satellite product, where the
    band the target absorbs most strongly is placed so the target reads as a
    distinct hue rather than as a brightness change.
    """
    r = percentile_stretch(b940, tiles, mask=mask)
    g = percentile_stretch(b850, tiles, mask=mask)
    b = percentile_stretch(b760, tiles, mask=mask)
    return np.stack([r, g, b], axis=-1)
