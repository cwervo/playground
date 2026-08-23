"""End-to-end pipeline: photograph -> synthetic vein-finder NIR imagery.

    load + orient
      -> CIELAB
      -> adaptive overlapping quadtree
      -> guided denoise of chroma
      -> probabilistic hand segmentation (tiled MAP-EM, mean-field, contours)
      -> CIELAB chromophore inversion (melanin, blood, shading)
      -> venous oxygenation model
      -> forward render at 760 / 850 / 940 nm
      -> per-tile DOS + stretch, NDVI/NDWI/MAVI, tasseled cap, MNF
      -> FDR-calibrated probabilistic vein contours

What this is and is not: the NIR bands are *simulated*, not measured. The
pipeline recovers a physically parameterised chromophore field from visible
colour and re-renders it at NIR wavelengths. Where melanin absorption falls off
as lambda^-3.33 while haemoglobin's 758 nm band does not, that re-rendering
genuinely raises blood contrast relative to pigment contrast -- which is why a
real vein finder works. But it cannot invent structure that left no trace in the
source photograph. Read the output as a physically-motivated re-weighting of
evidence already in the frame, not as a measurement of this hand's veins.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass, field as dc_field
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage

from . import colorimetry as C
from . import filters as F
from . import probcontour as P
from . import quadtree as Q
from . import rsindices as RS
from . import skin
from . import vessel
from . import noise as nz


@dataclass
class Config:
    max_side: int = 1400
    cct_k: float = 6500.0
    min_tile: int = 20
    max_depth: int = 6
    detail_thresh: float = 0.015
    overlap: float = 0.35
    guided_radius: int = 4
    guided_eps: float = 2e-3
    mf_sigma: float = 2.5
    mf_iter: int = 3
    fdr_q: float = 0.05
    vein_prior: float = 0.10
    roi_erode: int = 12
    vessel_scales: tuple = (1.5, 2.5, 3.5, 5.0)
    crest_gamma: float = 0.35
    n_null: int = 3            # surrogate frames for the empirical null
    n_perturb: int = 3         # noise redraws for the stability estimate
    support_dprime: float = 1.0   # modelled contrast / propagated index noise
    support_lum_snr: float = 4.0  # photometric floor, rules out inversion collapse
    sto2_venous: float = 0.55
    sto2_arterial: float = 0.95
    seed: int = 0


@dataclass
class Result:
    cfg: Config
    rgb: np.ndarray
    lab: np.ndarray
    tiles: list
    fields: dict = dc_field(default_factory=dict)
    meta: dict = dc_field(default_factory=dict)


def load_image(path: str, max_side: int) -> np.ndarray:
    """Load, apply EXIF orientation, downscale. Returns float sRGB in [0,1]."""
    im = Image.open(path)
    im = ImageOps.exif_transpose(im).convert("RGB")
    w, h = im.size
    scale = max_side / max(w, h)
    if scale < 1.0:
        im = im.resize((max(1, int(round(w * scale))),
                        max(1, int(round(h * scale)))), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def segment_hand(lab: np.ndarray, resid: np.ndarray, tiles: list,
                 cfg: Config) -> tuple:
    """Probabilistic hand segmentation in a three-feature space.

    darkness    -L*, since the hand is a shadowed foreground object against a
                sunlit wall
    smoothness  negative local detail; the hand is the nearest object and is
                defocused and motion-blurred, the background clutter is not
    skin-likeness  negative CIELAB chroma-plane residual against the skin
                model's locus -- a colour the two-layer model cannot reach is
                not skin

    Each feature is standardised before the mixture is fitted so no single one
    dominates the covariance.
    """
    L = lab[..., 0] / 100.0
    detail = F.local_detail(L, r=3)
    feats = np.stack([
        -L,
        -np.log1p(detail / (np.median(detail) + 1e-6)),
        -np.log1p(resid / (np.median(resid) + 1e-6)),
    ], axis=-1)
    mu = feats.reshape(-1, 3).mean(0)
    sd = feats.reshape(-1, 3).std(0) + 1e-9
    feats = (feats - mu) / sd

    prob, gm, sep = P.tiled_posterior(feats, tiles, order_by=0, tau=0.5,
                                      seed=cfg.seed)
    prob = P.meanfield_smooth(prob, sigma=cfg.mf_sigma, n_iter=cfg.mf_iter)

    # The hand is one object: keep the dominant connected component of the
    # thresholded posterior, close small holes, but return the *probability*
    # field so downstream contours stay probabilistic.
    core = P.largest_component(prob > 0.5, keep=1)
    core = ndimage.binary_closing(core, np.ones((9, 9)))
    core = ndimage.binary_fill_holes(core)
    return prob, core, gm, sep


def oxygenation_field(c_blood: np.ndarray, lab: np.ndarray,
                      mask: np.ndarray, cfg: Config) -> np.ndarray:
    """Assign a haemoglobin oxygen saturation to every pixel.

    Visible-light colour cannot measure StO2 through skin, so this is an
    explicit model, not a retrieval. It encodes one assumption: blood that
    reads as *excess* relative to the local perfusion background, and that is
    spatially smooth, is more likely to be a subpapillary venous plexus vessel
    than capillary bed -- deeper structures are blurred by dermal scattering,
    superficial ones are not. Those pixels are pushed toward venous saturation,
    the rest toward arterial.
    """
    b = np.log(np.maximum(c_blood, 1e-6))
    background = ndimage.median_filter(b, size=25)
    excess = b - background
    smooth = ndimage.gaussian_filter(excess, 2.0)

    ref = smooth[mask] if mask.any() else smooth
    lo, hi = np.percentile(ref, [50, 97])
    v = np.clip((smooth - lo) / max(hi - lo, 1e-9), 0.0, 1.0)
    return cfg.sto2_arterial + (cfg.sto2_venous - cfg.sto2_arterial) * v


def run(path: str, cfg: Config, verbose: bool = True) -> Result:
    t0 = time.time()
    log = (lambda *a: print(f"[{time.time() - t0:6.1f}s]", *a, flush=True)) \
        if verbose else (lambda *a: None)

    rgb = load_image(path, cfg.max_side)
    h, w, _ = rgb.shape
    log(f"loaded {w}x{h}")

    lab = C.srgb_to_lab(rgb)
    lin = C.srgb_decode(rgb)
    guide = lab[..., 0] / 100.0

    tiles = Q.build(guide, min_size=cfg.min_tile, max_depth=cfg.max_depth,
                    detail_thresh=cfg.detail_thresh, overlap=cfg.overlap)
    qstats = Q.stats(tiles, (h, w))
    log(f"quadtree: {qstats['n_leaves']} leaves, depth "
        f"{qstats['depth_min']}-{qstats['depth_max']}, "
        f"mean overlap x{qstats['mean_overlap_factor']:.2f}")

    def denoise_linear(linear: np.ndarray) -> np.ndarray:
        """Guided denoise of the CIELAB chroma channels, luminance untouched.

        Defined once and applied to the observed frame and to every surrogate
        alike. That matters: an earlier version denoised only the observed path,
        which made the empirical null strictly noisier than the data it was
        meant to calibrate and inverted the comparison.
        """
        lab_l = C.xyz_to_lab(C.rgb_to_xyz(linear))
        g = lab_l[..., 0] / 100.0
        out = lab_l.copy()
        for c in (1, 2):
            out[..., c] = F.guided_filter(g, lab_l[..., c],
                                          r=cfg.guided_radius,
                                          eps=cfg.guided_eps)
        return np.clip(C.xyz_to_rgb(C.lab_to_xyz(out)), 1e-7, None)

    lin_d = denoise_linear(lin)
    lab_d = C.xyz_to_lab(C.rgb_to_xyz(lin_d))
    log("guided chroma denoise done")

    renderer = C.SpectralRenderer(cfg.cct_k)
    lut = skin.SkinLUT(renderer)
    log(f"skin LUT: {lut.chroma.shape[0]} entries")

    c_mel, c_blood, resid, shading = lut.invert(lin_d)
    log("CIELAB chromophore inversion done")

    hand_p, hand_mask, gm, sep = segment_hand(lab, resid, tiles, cfg)
    log(f"hand segmentation: {100 * hand_mask.mean():.1f}% of frame, "
        f"global class separation {gm.separation(0):.2f}")

    sto2 = oxygenation_field(c_blood, lab, hand_mask, cfg)
    c_water = np.full_like(c_mel, 0.65)

    bands = skin.synthesize_nir(c_mel, c_blood, sto2, c_water)
    log("NIR bands synthesised at 760 / 850 / 940 nm")

    # Per-tile dark-object subtraction, then band math.
    bands_dos = {k: RS.dark_object_subtract(v, tiles) for k, v in bands.items()}
    b760, b850, b940 = (bands_dos["B760"], bands_dos["B850"], bands_dos["B940"])

    idx = {
        "NDVI_vein": RS.ndvi_vein(b760, b850),
        "NDWI_tissue": RS.ndwi_tissue(b850, b940),
        "SR": RS.simple_ratio(b760, b850),
        "MAVI": RS.mavi(b760, b850),
    }
    tc, tc_basis, _ = RS.tasseled_cap(bands_dos, mask=hand_mask)
    mnf_comps, mnf_snr, mnf_keys = RS.mnf(bands_dos, mask=hand_mask)
    log(f"MNF SNR eigenvalues: {np.round(mnf_snr, 2).tolist()}")

    # --- probabilistic vein contours ---
    # The statistic is a multiscale ridge response on the melanin-adjusted vein
    # index, not a high-pass of it. A high-pass fires hardest on the hand's
    # silhouette and the gaps between fingers, which are step edges; a vein is a
    # curvilinear ridge a few pixels wide. Analysis is confined to an eroded
    # interior so the silhouette itself cannot be scored at all.
    roi = ndimage.binary_erosion(hand_mask, np.ones((3, 3)),
                                 iterations=cfg.roi_erode)

    sigma_lin = nz.estimate_noise_sigma(rgb)

    def vein_index_of(linear: np.ndarray) -> np.ndarray:
        """invert -> synthesise -> index, holding the modelled StO2 fixed.

        StO2 is a modelled field rather than a measurement, so it is held
        constant across noise realisations; only the retrieved chromophores are
        allowed to move. Only the two bands the index needs are rendered.
        """
        cm, cb, _, _ = lut.invert(denoise_linear(linear))
        bb = skin.synthesize_nir(cm, cb, sto2, c_water, bands=("B760", "B850"))
        return ndimage.gaussian_filter(RS.mavi(bb["B760"], bb["B850"]), 1.0)

    def ridge_of(index: np.ndarray) -> np.ndarray:
        v, _ = vessel.vesselness(index, scales=tuple(cfg.vessel_scales),
                                 mask=roi, gamma=cfg.crest_gamma)
        return v * roi

    vein_index = vein_index_of(lin)
    vness, vscale = vessel.vesselness(vein_index, scales=tuple(cfg.vessel_scales),
                                      mask=roi, gamma=cfg.crest_gamma)
    vness = vness * roi

    # Empirical null: identical machinery on structure-free surrogates that
    # carry the measured noise. Anything it finds there is a false positive.
    nulls = [ridge_of(vein_index_of(f))
             for f in nz.surrogate_frames(rgb, sigma_lin, cfg.n_null,
                                          smooth=9.0, seed=cfg.seed)]
    log(f"empirical null: {cfg.n_null} surrogate frames, "
        f"null ridge mean {np.mean([n[roi].mean() for n in nulls]):.4f} "
        f"vs observed {vness[roi].mean():.4f}")

    # Stability: redraw the noise on the *real* frame and see what survives.
    rng = np.random.default_rng(cfg.seed + 1)
    perturbed_idx = [vein_index_of(
        np.clip(lin + rng.normal(0, 1, lin.shape) * sigma_lin, 1e-7, None))
        for _ in range(cfg.n_perturb)]
    perturbed = [ridge_of(ix) for ix in perturbed_idx]
    stab = nz.stability_snr(vness, perturbed)

    # Detectability: the index contrast a real vessel would produce, divided by
    # the noise actually propagated onto that index. This replaces a raw
    # code-value SNR, which mis-scores well-exposed saturated skin because its
    # blue channel is legitimately small.
    sigma_index = np.std(np.stack(perturbed_idx, axis=0), axis=0)
    delta_ref = skin.reference_vein_contrast(
        c_mel=float(np.median(c_mel[hand_mask])) if hand_mask.any() else 0.11)
    dprime = delta_ref / (sigma_index + 1e-12)
    data_snr = dprime

    # d' alone is not sufficient. Below a few code values the LUT inversion
    # collapses into a corner of the table: it stops responding to the input,
    # so a noise redraw barely moves it and sigma_index becomes small for the
    # worst possible reason. A photometric gate on luminance SNR rules that
    # degenerate regime out, so support requires both enough photons and enough
    # modelled contrast relative to propagated noise.
    y_obs = C.rgb_to_xyz(lin)[..., 1]
    sigma_y = np.sqrt((C.rgb_to_xyz(sigma_lin ** 2)[..., 1]).clip(0))
    lum_snr = ndimage.median_filter(y_obs / np.maximum(sigma_y, 1e-12), size=5)
    support = roi & (dprime >= cfg.support_dprime) & (lum_snr >= cfg.support_lum_snr)
    support_curve = {float(t): float((roi & (dprime >= cfg.support_dprime)
                                      & (lum_snr >= t)).sum()
                                     / max(roi.sum(), 1))
                     for t in (1.0, 2.0, 3.0, 5.0, 10.0)}
    log(f"reference vein index contrast {delta_ref:.4f}; detectable fraction of "
        "hand interior: " + ", ".join(f"lumSNR>={t:g}: {100 * v:.1f}%"
                                      for t, v in support_curve.items()))

    pvals = nz.empirical_p(vness, nulls, roi)
    p_in = pvals[support] if support.any() else pvals[roi]
    p_thresh = P.bh_threshold(p_in, cfg.fdr_q)

    vein_post = P.posterior_from_p(pvals, prior=cfg.vein_prior)
    vein_post = P.meanfield_smooth(vein_post, sigma=1.4, n_iter=3)
    # A detection is only reported where the data can support one at all.
    vein_post = vein_post * support
    n_sig = int(((pvals <= p_thresh) & support).sum()) if p_thresh > 0 else 0
    log(f"vein ridges: BH q={cfg.fdr_q} -> p<={p_thresh:.3g}, {n_sig} px "
        f"({100 * n_sig / max(support.sum(), 1):.2f}% of measurable support)")

    stat = vness
    fc = RS.false_color(b760, b850, b940, tiles=tiles, mask=hand_mask)

    fields = dict(
        lab=lab, lab_denoised=lab_d, guide=guide,
        c_mel=c_mel, c_blood=c_blood, resid=resid, shading=shading, sto2=sto2,
        hand_p=hand_p, hand_mask=hand_mask, tile_sep=sep,
        false_color=fc, vein_stat=stat, vein_p=pvals,
        vein_post=vein_post, vein_index=vein_index, vein_scale=vscale,
        roi=roi, support=support, data_snr=data_snr, stability=stab,
        sigma_index=sigma_index, dprime=dprime, lum_snr=lum_snr,
        null_ridge=nulls[0],
        **{f"raw_{k}": v for k, v in bands.items()},
        **bands_dos, **idx, **tc,
        **mnf_comps,
    )
    meta = dict(
        source=str(path), shape=[h, w], config=cfg.__dict__,
        quadtree=qstats,
        hand_fraction=float(hand_mask.mean()),
        class_separation=float(gm.separation(0)),
        mnf_snr=[float(v) for v in mnf_snr],
        tasseled_cap_basis=tc_basis.tolist(),
        band_keys=mnf_keys,
        bh_p_threshold=float(p_thresh),
        vein_px=n_sig,
        vein_fraction_of_support=float(n_sig / max(support.sum(), 1)),
        roi_fraction=float(roi.mean()),
        support_fraction_of_roi=float(support.sum() / max(roi.sum(), 1)),
        median_data_snr_in_roi=float(np.median(data_snr[roi])) if roi.any() else 0.0,
        support_curve=support_curve,
        reference_vein_contrast=float(delta_ref),
        null_ridge_mean=float(np.mean([n[roi].mean() for n in nulls])),
        observed_ridge_mean=float(vness[roi].mean()),
        median_stability_in_support=float(np.median(stab[support]))
            if support.any() else 0.0,
        band_means_in_hand={k: float(v[hand_mask].mean())
                            for k, v in bands.items()} if hand_mask.any() else {},
        runtime_s=round(time.time() - t0, 2),
    )
    log(f"done in {meta['runtime_s']}s")
    return Result(cfg=cfg, rgb=rgb, lab=lab, tiles=tiles, fields=fields, meta=meta)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image")
    ap.add_argument("-o", "--outdir", default="synthetic_nir/out")
    ap.add_argument("--max-side", type=int, default=Config.max_side)
    ap.add_argument("--max-depth", type=int, default=Config.max_depth)
    ap.add_argument("--min-tile", type=int, default=Config.min_tile)
    ap.add_argument("--overlap", type=float, default=Config.overlap)
    ap.add_argument("--detail-thresh", type=float, default=Config.detail_thresh)
    ap.add_argument("--cct", type=float, default=Config.cct_k)
    ap.add_argument("--fdr-q", type=float, default=Config.fdr_q)
    args = ap.parse_args(argv)

    cfg = Config(max_side=args.max_side, max_depth=args.max_depth,
                 min_tile=args.min_tile, overlap=args.overlap,
                 detail_thresh=args.detail_thresh, cct_k=args.cct,
                 fdr_q=args.fdr_q)
    res = run(args.image, cfg)

    from . import render
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    render.write_all(res, outdir)
    (outdir / "metadata.json").write_text(json.dumps(res.meta, indent=2))
    print(f"wrote {outdir}")
    return res


if __name__ == "__main__":
    main()
