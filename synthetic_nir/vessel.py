"""Multiscale Hessian ridge filtering (Frangi vesselness).

Why this and not a high-pass. A vein is a *curvilinear ridge* a few pixels
across. Subtracting a local median from an index image responds to any
departure from the local background, and the largest such departures in this
frame are the hand's silhouette and the boundaries between fingers -- step
edges, not ridges. A first attempt at the detection stage did exactly that and
flagged 17% of the hand, almost all of it outline.

The Hessian separates the two cases. At a bright ridge one principal curvature
is strongly negative and the other is near zero; at a step edge both are
comparable. Frangi's blobness ratio R_B = |l1| / |l2| is precisely that
discriminant, and the structureness term S suppresses the flat noise floor.
Taking the maximum over a range of scales makes the response independent of
vessel calibre.

Frangi, Niessen, Vincken & Viergever (1998), "Multiscale vessel enhancement
filtering", MICCAI.
"""

from __future__ import annotations

import numpy as np
from scipy import ndimage


def hessian(a: np.ndarray, sigma: float) -> tuple:
    """Scale-normalised second derivatives at one scale."""
    g = lambda o: ndimage.gaussian_filter(a, sigma, order=o, mode="nearest")
    s2 = sigma ** 2
    return s2 * g((2, 0)), s2 * g((1, 1)), s2 * g((0, 2))


def eigenvalues(hxx, hxy, hyy) -> tuple:
    """Eigenvalues of a symmetric 2x2 field, ordered by absolute magnitude."""
    tmp = np.sqrt(np.maximum((hxx - hyy) ** 2 + 4.0 * hxy * hxy, 0.0))
    l1 = 0.5 * (hxx + hyy + tmp)
    l2 = 0.5 * (hxx + hyy - tmp)
    swap = np.abs(l1) > np.abs(l2)
    small = np.where(swap, l2, l1)
    large = np.where(swap, l1, l2)
    return small, large


def vesselness(a: np.ndarray, scales=(1.5, 2.5, 3.5, 5.0), beta: float = 0.5,
               c: float | None = None, bright: bool = True,
               mask: np.ndarray | None = None,
               crest_gate: bool = True, gamma: float = 0.35) -> tuple:
    """Frangi vesselness, maximised over scales, with a ridge-crest gate.

    gamma       crest tolerance, dimensionless (see below)
    bright      True to detect ridges brighter than their surroundings (which
                is the case here: venous blood *raises* the vein index)
    mask        restricts the adaptive constants to a region, so the noise
                floor is calibrated on tissue rather than on background
    crest_gate  suppress the shoulders of step edges (see below)

    Plain Frangi is not enough on this image. A Gaussian-smoothed step edge has
    shoulders where one curvature is large and the other near zero -- locally
    indistinguishable from half a ridge -- so the hand's silhouette scores
    almost as highly as a vessel. Measured on a synthetic ridge-plus-edge test
    the ratio was only 1.8x.

    The crest condition fixes it. Eberly's definition of a ridge point requires
    the gradient to be orthogonal to the direction of greatest curvature: at a
    crest you are at a maximum *across* the ridge, so the across-ridge
    derivative vanishes. On an edge shoulder it is maximal. Projecting the
    scale-normalised gradient onto the major eigenvector and damping the
    response by it separates the two cleanly.

    Returns (response in [0, 1], scale of maximal response per pixel).
    """
    best = np.zeros_like(a, dtype=float)
    best_scale = np.zeros_like(a, dtype=float)
    for s in scales:
        hxx, hxy, hyy = hessian(a, s)
        l_small, l_large = eigenvalues(hxx, hxy, hyy)
        rb = np.abs(l_small) / np.maximum(np.abs(l_large), 1e-12)
        struct = np.sqrt(l_small ** 2 + l_large ** 2)

        if c is None:
            ref = struct[mask] if mask is not None and mask.any() else struct
            c_s = 0.5 * float(np.percentile(ref, 99.0))
        else:
            c_s = c
        c_s = max(c_s, 1e-12)

        v = (np.exp(-(rb ** 2) / (2 * beta ** 2))
             * (1.0 - np.exp(-(struct ** 2) / (2 * c_s ** 2))))
        # Wrong-signed curvature means it is not the polarity of ridge we want.
        v = np.where(l_large > 0 if bright else l_large < 0, 0.0, v)

        if crest_gate:
            # Major eigenvector = across-ridge direction. For [[hxx,hxy],
            # [hxy,hyy]] with eigenvalue l_large, (hxy, l_large - hxx) is an
            # eigenvector; fall back to (l_large - hyy, hxy) where the first
            # degenerates.
            ex, ey = hxy, l_large - hxx
            alt_x, alt_y = l_large - hyy, hxy
            degenerate = (ex * ex + ey * ey) < (alt_x * alt_x + alt_y * alt_y)
            ex = np.where(degenerate, alt_x, ex)
            ey = np.where(degenerate, alt_y, ey)
            norm = np.sqrt(ex * ex + ey * ey) + 1e-12
            ex, ey = ex / norm, ey / norm

            gx = s * ndimage.gaussian_filter(a, s, order=(1, 0), mode="nearest")
            gy = s * ndimage.gaussian_filter(a, s, order=(0, 1), mode="nearest")
            # Made dimensionless against the curvature that produced it: for a
            # ridge of amplitude A and width sigma the scale-normalised
            # gradient goes as A/sigma * s and the scale-normalised curvature as
            # A, so q = |g_across| / |l_large| is scale-free -- it vanishes at a
            # crest and is O(1) on an edge shoulder. A fixed gamma therefore
            # means the same thing at every scale and every contrast.
            across = np.abs(gx * ex + gy * ey)
            q = across / (np.abs(l_large) + 1e-12)
            v = v * np.exp(-(q ** 2) / (2.0 * gamma ** 2))

        upd = v > best
        best = np.where(upd, v, best)
        best_scale = np.where(upd, s, best_scale)
    return best, best_scale


def ridge_orientation(a: np.ndarray, sigma: float = 2.5) -> np.ndarray:
    """Local ridge direction in radians, from the Hessian's minor eigenvector."""
    hxx, hxy, hyy = hessian(a, sigma)
    return 0.5 * np.arctan2(2.0 * hxy, hxx - hyy)
