"""Sensor-noise estimation and empirical null calibration.

This module exists because of what the source photograph actually contains.
Measured at full resolution on the 8-bit file, the palm sits at a mean sRGB
code of about (1.2, 0.5, 0.5) out of 255 and the back of the hand at
(7.5, 2.6, 1.4); only the sunlit finger surfaces reach (95, 90, 76). Over most
of the hand the colour that the CIELAB inversion consumes is quantisation
noise, not skin chroma.

An analysis that ignores that will happily draw confident-looking contours
around amplified noise -- and a first version of this pipeline did exactly
that. So the detector is calibrated against an *empirical* null instead of an
assumed Gaussian one:

  * estimate the per-pixel, per-channel sensor noise actually present;
  * build surrogate frames that contain the same noise but, by construction, no
    fine structure -- the scene is smoothed well beyond the detector's largest
    scale before the noise is added back;
  * push each surrogate through the identical inversion, NIR synthesis, index
    and ridge filter;
  * the pooled ridge responses from the surrogates are the null distribution.

A p-value is then the fraction of null responses at least as large as the
observed one. Nothing about the shape of that distribution has to be assumed,
and every non-linearity in the chain -- the cube root in CIELAB, the LUT
nearest-neighbour match, the Kubelka-Munk square root, the Hessian filter -- is
represented exactly, because the surrogates go through the same code.
"""

from __future__ import annotations

import numpy as np
from scipy import ndimage

from .colorimetry import srgb_decode


def estimate_noise_sigma(srgb: np.ndarray, tiles=None,
                         quant_floor: bool = True) -> np.ndarray:
    """Per-pixel, per-channel noise standard deviation in *linear* units.

    The estimate is made in the gamma-encoded domain, where sensor noise is
    closest to stationary, and then transformed to linear light through the
    local slope of the sRGB decoding curve. That slope is what makes shadow
    noise so damaging: near code zero it is small, so a linear-domain sigma
    looks tiny, but the *relative* uncertainty explodes.

    Two contributions are combined:
      * an empirical high-frequency estimate, via the median absolute deviation
        of a Laplacian (robust to real edges, unlike a plain variance);
      * a quantisation floor of 1/(255 sqrt(12)), which dominates in the
        near-black regions of this frame.
    """
    h, w, _ = srgb.shape
    sigma_enc = np.zeros_like(srgb, dtype=np.float64)
    for c in range(3):
        a = srgb[..., c].astype(np.float64)
        lap = (4 * a[1:-1, 1:-1] - a[:-2, 1:-1] - a[2:, 1:-1]
               - a[1:-1, :-2] - a[1:-1, 2:])
        # Laplacian of white noise has variance 20 sigma^2.
        local = ndimage.median_filter(np.abs(lap), size=7) * 1.4826 / np.sqrt(20.0)
        s = np.zeros((h, w))
        s[1:-1, 1:-1] = local
        s[0, :], s[-1, :], s[:, 0], s[:, -1] = s[1, :], s[-2, :], s[:, 1], s[:, -2]
        sigma_enc[..., c] = ndimage.gaussian_filter(s, 3.0)

    if quant_floor:
        sigma_enc = np.maximum(sigma_enc, 1.0 / (255.0 * np.sqrt(12.0)))

    # d(linear)/d(encoded), evaluated pixelwise.
    u = np.clip(srgb, 0.0, 1.0)
    slope = np.where(u <= 0.04045, 1.0 / 12.92,
                     2.4 * ((u + 0.055) / 1.055) ** 1.4 / 1.055)
    return sigma_enc * slope


def surrogate_frames(srgb: np.ndarray, sigma_lin: np.ndarray, n: int,
                     smooth: float = 9.0, seed: int = 0):
    """Yield `n` linear-RGB frames with the same noise but no fine structure.

    The scene is blurred well past the detector's largest scale, so a ridge
    filter has nothing real to find; then noise of the measured magnitude is
    added back. Anything the detector reports on these frames is, by
    construction, a false positive.
    """
    rng = np.random.default_rng(seed)
    base = srgb_decode(srgb)
    smoothed = np.stack([ndimage.gaussian_filter(base[..., c], smooth,
                                                 mode="nearest")
                         for c in range(3)], axis=-1)
    for _ in range(n):
        yield np.clip(smoothed + rng.normal(0.0, 1.0, base.shape) * sigma_lin,
                      1e-7, None)


def empirical_p(observed: np.ndarray, null_samples: list[np.ndarray],
                roi: np.ndarray) -> np.ndarray:
    """One-sided p-values against a pooled empirical null.

    p = (1 + #{null >= observed}) / (1 + N), the standard add-one estimator,
    which keeps p strictly positive so downstream logs stay finite.
    """
    pool = np.concatenate([s[roi].ravel() for s in null_samples])
    pool.sort()
    n = pool.size
    idx = np.searchsorted(pool, observed.ravel(), side="left")
    return ((1.0 + (n - idx)) / (1.0 + n)).reshape(observed.shape)


def stability_snr(observed: np.ndarray, perturbed: list[np.ndarray],
                  eps: float = 1e-6) -> np.ndarray:
    """Ratio of the observed response to its scatter under resampled noise.

    Large where the response is driven by structure that survives a noise
    redraw; near zero where the response is itself a noise artefact.
    """
    stack = np.stack(perturbed, axis=0)
    return observed / (stack.std(axis=0) + eps)
