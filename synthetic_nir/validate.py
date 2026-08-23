"""Positive control: does the detector find veins that are known to be there?

A negative result on the real photograph is only worth reporting if the same
machinery demonstrably succeeds when the signal exists. So this module builds a
phantom whose ground truth is known exactly, renders it to 8-bit sRGB through
the *same* forward model the pipeline inverts, adds realistic sensor noise at a
chosen exposure, and then runs the identical detection stage.

Sweeping the exposure answers the question that matters for the real image:
at what exposure does this method stop working, and which side of that line is
the photograph on?
"""

from __future__ import annotations

import numpy as np
from scipy import ndimage

from . import colorimetry as C
from . import filters as F
from . import noise as nz
from . import probcontour as P
from . import quadtree as Q
from . import rsindices as RS
from . import skin
from . import vessel


def phantom(shape=(420, 320), seed: int = 0) -> dict:
    """A slab of skin carrying a known venous network.

    Veins are drawn as smooth curvilinear tracks of raised blood volume and
    lowered oxygen saturation -- the physical signature a vein finder looks
    for. Calibres span 3 to 7 px so the multiscale filter is genuinely tested.
    """
    h, w = shape
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)

    tissue = ((yy - h / 2) / (h * 0.44)) ** 2 + ((xx - w / 2) / (w * 0.40)) ** 2 < 1.0

    truth = np.zeros((h, w))
    tracks = [
        (0.20, 0.35, 0.95, 0.55, 3.0), (0.15, 0.60, 0.90, 0.72, 2.2),
        (0.35, 0.50, 0.80, 0.30, 1.7), (0.55, 0.42, 0.95, 0.80, 1.4),
        (0.30, 0.75, 0.70, 0.45, 1.2),
    ]
    for y0, x0, y1, x1, rad in tracks:
        t = np.linspace(0, 1, 400)
        wob = 0.05 * np.sin(2 * np.pi * t * rng.uniform(1.0, 2.2)
                            + rng.uniform(0, 6.28))
        py = (y0 + (y1 - y0) * t + wob) * h
        px = (x0 + (x1 - x0) * t + wob * 0.7) * w
        for a, b in zip(py, px):
            d2 = (yy - a) ** 2 + (xx - b) ** 2
            truth = np.maximum(truth, np.exp(-d2 / (2 * rad ** 2)))

    truth *= tissue
    vein = truth > 0.5

    c_mel = np.where(tissue, 0.11, 0.02) + 0.012 * ndimage.gaussian_filter(
        rng.normal(0, 1, (h, w)), 12)
    c_blood = np.where(tissue, 0.020, 0.001) + 0.070 * truth
    sto2 = np.where(tissue, 0.90, 0.90) - 0.35 * truth
    c_water = np.full((h, w), 0.65)
    return dict(tissue=tissue, vein=vein, truth=truth, c_mel=np.clip(c_mel, 0.005, 0.5),
                c_blood=c_blood, sto2=sto2, c_water=c_water)


def render_8bit(ph: dict, renderer: C.SpectralRenderer, exposure: float,
                seed: int = 0, read_noise_codes: float = 1.0) -> np.ndarray:
    """Render the phantom to a quantised 8-bit sRGB frame at a given exposure.

    `exposure` multiplies scene linear radiance before encoding, so exposure=1
    puts mid skin around code 150 and exposure=0.01 reproduces the few-code-value
    regime measured in the real photograph. Poisson-like shot noise scaled with
    signal plus a fixed read term are applied in the linear domain, then the
    result is gamma-encoded and rounded to 8 bits -- the same chain that
    produced the source image.
    """
    h, w = ph["tissue"].shape
    p = skin.SkinParams(ph["c_mel"].ravel(), ph["c_blood"].ravel(),
                        ph["sto2"].ravel(), ph["c_water"].ravel())
    refl = skin.reflectance(p)
    lin = renderer.to_linear_rgb(refl).reshape(h, w, 3)
    lin = np.clip(lin, 0.0, None) * exposure

    rng = np.random.default_rng(seed)
    full_well = 12000.0
    e = np.clip(lin, 0, None) * full_well
    read = read_noise_codes / 255.0 * full_well
    noisy = (e + rng.normal(0, 1, e.shape) * np.sqrt(e + read ** 2)) / full_well
    return np.round(np.clip(C.srgb_encode(np.clip(noisy, 0, 1)), 0, 1)
                    * 255.0) / 255.0


def detect(srgb: np.ndarray, cfg, renderer, lut, roi: np.ndarray,
           n_null: int = 3, seed: int = 0) -> dict:
    """The pipeline's detection stage, standalone, on a given frame."""
    lin = np.clip(C.srgb_decode(srgb), 1e-7, None)
    tiles = Q.build(C.xyz_to_lab(C.rgb_to_xyz(lin))[..., 0] / 100.0,
                    min_size=cfg.min_tile, max_depth=4,
                    detail_thresh=cfg.detail_thresh, overlap=cfg.overlap)

    def denoise(x):
        lab = C.xyz_to_lab(C.rgb_to_xyz(x))
        g = lab[..., 0] / 100.0
        out = lab.copy()
        for c in (1, 2):
            out[..., c] = F.guided_filter(g, lab[..., c], r=cfg.guided_radius,
                                          eps=cfg.guided_eps)
        return np.clip(C.xyz_to_rgb(C.lab_to_xyz(out)), 1e-7, None)

    sto2_fixed = np.full(srgb.shape[:2], 0.75)
    water = np.full(srgb.shape[:2], 0.65)

    def index_of(x):
        cm, cb, _, _ = lut.invert(denoise(x))
        bb = skin.synthesize_nir(cm, cb, sto2_fixed, water,
                                 bands=("B760", "B850"))
        return ndimage.gaussian_filter(RS.mavi(bb["B760"], bb["B850"]), 1.0)

    def ridge_of(ix):
        v, _ = vessel.vesselness(ix, scales=tuple(cfg.vessel_scales), mask=roi,
                                 gamma=cfg.crest_gamma)
        return v * roi

    sigma = nz.estimate_noise_sigma(srgb)
    obs_idx = index_of(lin)
    obs = ridge_of(obs_idx)
    nulls = [ridge_of(index_of(f))
             for f in nz.surrogate_frames(srgb, sigma, n_null, smooth=9.0,
                                          seed=seed)]
    rng = np.random.default_rng(seed + 1)
    pert_idx = [index_of(np.clip(lin + rng.normal(0, 1, lin.shape) * sigma,
                                 1e-7, None)) for _ in range(n_null)]
    sigma_index = np.std(np.stack(pert_idx, axis=0), axis=0)
    delta_ref = skin.reference_vein_contrast()
    data_snr = delta_ref / (sigma_index + 1e-12)
    y_obs = C.rgb_to_xyz(lin)[..., 1]
    sigma_y = np.sqrt((C.rgb_to_xyz(sigma ** 2)[..., 1]).clip(0))
    lum_snr = ndimage.median_filter(y_obs / np.maximum(sigma_y, 1e-12), size=5)
    pv = nz.empirical_p(obs, nulls, roi)
    support = roi & (data_snr >= cfg.support_dprime) & (lum_snr >= cfg.support_lum_snr)
    return dict(ridge=obs, p=pv, support=support, data_snr=data_snr,
                lum_snr=lum_snr,
                null_mean=float(np.mean([n[roi].mean() for n in nulls])),
                obs_mean=float(obs[roi].mean()))


def auc(score: np.ndarray, truth: np.ndarray, roi: np.ndarray) -> float:
    """Rank-based ROC AUC (Mann-Whitney), no thresholding involved."""
    s = score[roi].ravel()
    t = truth[roi].ravel().astype(bool)
    if t.sum() == 0 or (~t).sum() == 0:
        return float("nan")
    order = np.argsort(s, kind="mergesort")
    ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.arange(1, s.size + 1)
    # average ranks over ties
    uniq, inv, counts = np.unique(s, return_inverse=True, return_counts=True)
    sums = np.zeros(uniq.size)
    np.add.at(sums, inv, ranks)
    ranks = (sums / counts)[inv]
    n1, n0 = t.sum(), (~t).sum()
    return float((ranks[t].sum() - n1 * (n1 + 1) / 2.0) / (n1 * n0))


def sweep(exposures=(1.0, 0.3, 0.1, 0.03, 0.01), cfg=None, q: float = 0.05,
          seed: int = 1, n_null: int = 3):
    """Run the detector across exposures on the phantom. Returns rows + assets."""
    from .pipeline import Config
    cfg = cfg or Config()
    renderer = C.SpectralRenderer(cfg.cct_k)
    lut = skin.SkinLUT(renderer)
    ph = phantom()
    roi = ndimage.binary_erosion(ph["tissue"], np.ones((3, 3)), iterations=6)
    rows, frames = [], {}
    for e in exposures:
        im = render_8bit(ph, renderer, e, seed=seed)
        d = detect(im, cfg, renderer, lut, roi, n_null=n_null, seed=seed + 1)
        a = auc(d["ridge"], ph["vein"], roi)
        sup = d["support"]
        p_in = d["p"][sup] if sup.any() else d["p"][roi]
        thr = P.bh_threshold(p_in, q)
        det = (d["p"] <= thr) & sup if thr > 0 else np.zeros_like(sup)
        vt = ph["vein"] & roi
        rows.append(dict(
            exposure=e, tissue_code=float((im * 255)[ph["tissue"]].mean()),
            auc=float(a), obs_ridge=d["obs_mean"], null_ridge=d["null_mean"],
            detectable_frac=float(sup.sum() / roi.sum()),
            recall=float(det[vt].sum() / max(vt.sum(), 1)),
            precision=float(det[vt].sum() / max(det.sum(), 1)),
            median_lum_snr=float(np.median(d["lum_snr"][roi]))))
        frames[e] = {**d, "srgb": im, "det": det}
    return rows, frames, ph, roi
