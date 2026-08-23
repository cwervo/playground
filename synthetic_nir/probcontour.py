"""Fast statistical probabilistic contouring.

The pipeline never thresholds an image. Every boundary it draws is an isoline
of a posterior probability field, built like this:

  1. a global two-component Gaussian mixture over a small feature stack gives
     prior class models (cheap, fitted on a subsample);
  2. each overlapping quadtree leaf refines those models with a few MAP-EM
     iterations, shrunk toward the global fit so a leaf that contains only one
     class cannot invent a spurious second one;
  3. per-leaf posteriors are feather-fused into one field, so every pixel is an
     average over several independent local fits;
  4. the fused field is regularised by mean-field smoothing of its logit, which
     is the closed-form update for a Gaussian-pairwise CRF;
  5. contours are marching-squares isolines of the result.

For the vein detection the class models are replaced by a robust null: a
per-leaf median/MAD fit to the *background* index, one-sided p-values against
it, and a Benjamini-Hochberg FDR threshold so the contour level is chosen by a
controlled false-discovery rate rather than by eye.
"""

from __future__ import annotations

import numpy as np
from scipy import ndimage

from .quadtree import Mosaic, Tile, feather

EPS = 1e-12


# --- Gaussian mixture --------------------------------------------------------

def _logpdf(x, mu, cov):
    d = x.shape[1]
    cov = cov + np.eye(d) * 1e-9
    L = np.linalg.cholesky(cov)
    diff = (x - mu).T
    sol = np.linalg.solve(L, diff)
    quad = (sol * sol).sum(axis=0)
    logdet = 2.0 * np.log(np.diag(L)).sum()
    return -0.5 * (quad + logdet + d * np.log(2 * np.pi))


class GaussianMixture2:
    """Two-component full-covariance mixture. Component 1 is the 'positive'
    class -- the one with the larger mean along `order_by`."""

    def __init__(self, weights, means, covs):
        self.weights = np.asarray(weights, float)
        self.means = np.asarray(means, float)
        self.covs = np.asarray(covs, float)

    @classmethod
    def fit(cls, x: np.ndarray, n_iter: int = 40, order_by: int = 0,
            seed: int = 0, init: "GaussianMixture2 | None" = None):
        x = np.atleast_2d(x)
        n, d = x.shape
        if init is None:
            # Split on the order_by feature at its median: a deterministic,
            # well-conditioned start that beats random init for bimodal data.
            piv = np.median(x[:, order_by])
            lo, hi = x[x[:, order_by] <= piv], x[x[:, order_by] > piv]
            if len(lo) < d + 2 or len(hi) < d + 2:
                lo, hi = x[: n // 2], x[n // 2:]
            means = np.stack([hi.mean(0), lo.mean(0)])
            covs = np.stack([np.cov(hi.T) + np.eye(d) * 1e-6,
                             np.cov(lo.T) + np.eye(d) * 1e-6])
            weights = np.array([0.5, 0.5])
        else:
            weights, means, covs = (init.weights.copy(), init.means.copy(),
                                    init.covs.copy())
        for _ in range(n_iter):
            lp = np.stack([np.log(weights[k] + EPS) + _logpdf(x, means[k], covs[k])
                           for k in range(2)], axis=1)
            m = lp.max(axis=1, keepdims=True)
            r = np.exp(lp - m)
            r /= r.sum(axis=1, keepdims=True)
            nk = r.sum(axis=0) + EPS
            weights = nk / n
            means = (r.T @ x) / nk[:, None]
            for k in range(2):
                diff = x - means[k]
                covs[k] = (diff * r[:, k:k + 1]).T @ diff / nk[k] + np.eye(d) * 1e-6
        gm = cls(weights, means, covs)
        return gm.ordered(order_by)

    def ordered(self, order_by: int):
        if self.means[0, order_by] < self.means[1, order_by]:
            return GaussianMixture2(self.weights[::-1], self.means[::-1],
                                    self.covs[::-1])
        return self

    def posterior(self, x: np.ndarray) -> np.ndarray:
        """P(component 0 | x)."""
        x = np.atleast_2d(x)
        lp = np.stack([np.log(self.weights[k] + EPS) + _logpdf(x, self.means[k],
                                                               self.covs[k])
                       for k in range(2)], axis=1)
        m = lp.max(axis=1, keepdims=True)
        r = np.exp(lp - m)
        return r[:, 0] / r.sum(axis=1)

    def separation(self, order_by: int = 0) -> float:
        """Standardised distance between components along one feature: how much
        evidence there is that two classes are actually present."""
        s = np.sqrt(self.covs[0, order_by, order_by]
                    + self.covs[1, order_by, order_by]) + EPS
        return float(abs(self.means[0, order_by] - self.means[1, order_by]) / s)


def map_em_refine(x: np.ndarray, prior: GaussianMixture2, tau: float = 0.5,
                  n_iter: int = 8, order_by: int = 0) -> GaussianMixture2:
    """A few EM steps shrunk toward a global prior.

    tau is the weight on the prior, expressed as a fraction of the local sample
    size. With tau = 0.5 a leaf has to be about twice as informative as the
    prior before it can move the class models much -- which is exactly the
    behaviour needed for leaves that contain only one of the two classes.
    """
    x = np.atleast_2d(x)
    n, d = x.shape
    weights, means, covs = (prior.weights.copy(), prior.means.copy(),
                            prior.covs.copy())
    n_prior = tau * n
    for _ in range(n_iter):
        lp = np.stack([np.log(weights[k] + EPS) + _logpdf(x, means[k], covs[k])
                       for k in range(2)], axis=1)
        m = lp.max(axis=1, keepdims=True)
        r = np.exp(lp - m)
        r /= r.sum(axis=1, keepdims=True)
        nk = r.sum(axis=0) + EPS
        weights = (nk + n_prior * prior.weights) / (n + n_prior)
        for k in range(2):
            mk = (r[:, k] @ x) / nk[k]
            means[k] = (nk[k] * mk + n_prior * prior.means[k]) / (nk[k] + n_prior)
            diff = x - means[k]
            ck = (diff * r[:, k:k + 1]).T @ diff / nk[k]
            covs[k] = ((nk[k] * ck + n_prior * prior.covs[k])
                       / (nk[k] + n_prior) + np.eye(d) * 1e-6)
    return GaussianMixture2(weights, means, covs).ordered(order_by)


# --- tiled posterior fusion --------------------------------------------------

def tiled_posterior(features: np.ndarray, tiles: list[Tile],
                    order_by: int = 0, tau: float = 0.5,
                    min_separation: float = 0.35,
                    subsample: int = 60000, seed: int = 0,
                    fit_mask: np.ndarray | None = None,
                    min_fit_px: int = 400) -> tuple:
    """Fuse per-leaf MAP-EM posteriors into one probability field.

    features: (h, w, d)
    fit_mask: if given, the mixture is *fitted* only on pixels inside it but is
              still *evaluated* everywhere. This matters for the vein stage:
              the classes of interest exist only inside the hand, and letting
              background pixels into the fit would define the second component
              as 'not hand' rather than 'vein'.

    Returns (probability, global_mixture, per_tile_separation_map).
    """
    h, w, d = features.shape
    flat = features.reshape(-1, d)
    fit_flat = flat[fit_mask.ravel()] if fit_mask is not None else flat
    if fit_flat.shape[0] < min_fit_px:
        fit_flat = flat
    rng = np.random.default_rng(seed)
    idx = (rng.choice(fit_flat.shape[0], subsample, replace=False)
           if fit_flat.shape[0] > subsample else slice(None))
    prior = GaussianMixture2.fit(fit_flat[idx], n_iter=60, order_by=order_by)

    mos = Mosaic((h, w))
    sep_mos = Mosaic((h, w))
    for t in tiles:
        sub = features[t.halo].reshape(-1, d)
        fit_sub = sub
        if fit_mask is not None:
            m_local = fit_mask[t.halo].ravel()
            fit_sub = sub[m_local] if m_local.sum() >= min_fit_px else None
        if fit_sub is None:
            mos.add(t, prior.posterior(sub).reshape(t.halo_shape))
            sep_mos.add(t, np.zeros(t.halo_shape))
            continue
        step = max(1, fit_sub.shape[0] // 20000)
        local = map_em_refine(fit_sub[::step], prior, tau=tau, order_by=order_by)
        sep = local.separation(order_by)
        # A leaf whose two components have collapsed onto each other holds no
        # local evidence; fall back to the global model there.
        model = local if sep >= min_separation else prior
        p = model.posterior(sub).reshape(t.halo_shape)
        mos.add(t, p)
        sep_mos.add(t, np.full(t.halo_shape, sep))
    return mos.result(), prior, sep_mos.result()


# --- regularisation ----------------------------------------------------------

def logit(p, eps=1e-6):
    p = np.clip(p, eps, 1 - eps)
    return np.log(p / (1 - p))


def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-z))


def meanfield_smooth(p: np.ndarray, sigma: float = 2.0, n_iter: int = 3,
                     coupling: float = 0.6) -> np.ndarray:
    """Mean-field regularisation of a probability field.

    For a CRF with Gaussian pairwise potentials the mean-field update is a
    convolution of the neighbours' expectations, so each iteration is one
    Gaussian blur of the current logit blended back into the data term.
    """
    z0 = logit(p)
    z = z0.copy()
    for _ in range(n_iter):
        msg = ndimage.gaussian_filter(sigmoid(z), sigma, mode="nearest")
        z = z0 + coupling * logit(msg)
    return sigmoid(z)


# --- robust null and FDR -----------------------------------------------------

def robust_z(x: np.ndarray, tiles: list[Tile], mask: np.ndarray | None = None,
             clip: float = 8.0) -> np.ndarray:
    """Per-leaf median/MAD standardisation, feather-fused.

    The MAD is scaled by 1.4826 so it estimates a Gaussian sigma. Masked pixels
    (i.e. the target class) are excluded from the null fit where enough
    background remains, so a tile that is mostly vein does not standardise the
    vein away.
    """
    mos = Mosaic(x.shape)
    for t in tiles:
        sub = x[t.halo]
        ref = sub
        if mask is not None:
            m = mask[t.halo]
            if m.sum() > 0.15 * m.size:
                ref = sub[m]
        med = np.median(ref)
        mad = np.median(np.abs(ref - med)) * 1.4826
        if not np.isfinite(mad) or mad < 1e-9:
            mad = np.std(ref) + 1e-9
        mos.add(t, np.clip((sub - med) / mad, -clip, clip))
    return mos.result()


def norm_sf(z: np.ndarray) -> np.ndarray:
    """One-sided Gaussian survival function, via erfc."""
    from scipy.special import erfc
    return 0.5 * erfc(z / np.sqrt(2.0))


def bh_threshold(p: np.ndarray, q: float = 0.05) -> float:
    """Benjamini-Hochberg critical p-value at false-discovery rate q.

    Returns 0.0 when nothing survives, which callers should read as 'no
    contour is defensible at this q'.
    """
    flat = np.sort(p.ravel())
    n = flat.size
    thresh = flat <= (np.arange(1, n + 1) / n) * q
    return float(flat[thresh][-1]) if thresh.any() else 0.0


def posterior_from_p(p: np.ndarray, prior: float = 0.08) -> np.ndarray:
    """Turn one-sided p-values into a posterior via a two-group Bayes factor.

    The null density at p is uniform; the alternative is modelled as Beta(a, 1)
    with a < 1, whose density is a p^(a-1). This is the standard
    'p-value to posterior' conversion and keeps the field calibrated enough for
    isolines to mean something.
    """
    a = 0.35
    lik_alt = a * np.clip(p, 1e-9, 1.0) ** (a - 1.0)
    return prior * lik_alt / (prior * lik_alt + (1.0 - prior))


# --- contour extraction ------------------------------------------------------

def contours(field: np.ndarray, levels) -> dict:
    """Marching-squares isolines, as {level: [(N,2) arrays of (x, y)]}."""
    from matplotlib.figure import Figure
    fig = Figure()
    ax = fig.add_subplot(111)
    cs = ax.contour(field, levels=list(levels))
    out = {}
    for lev, segs in zip(cs.levels, cs.allsegs):
        out[float(lev)] = [s for s in segs if len(s) > 8]
    return out


def largest_component(mask: np.ndarray, keep: int = 1) -> np.ndarray:
    lab, n = ndimage.label(mask)
    if n == 0:
        return mask
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    order = np.argsort(sizes)[::-1][:keep]
    return np.isin(lab, order + 1)
