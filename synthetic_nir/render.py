"""Figure composition for the synthetic NIR pipeline."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PatchCollection
from matplotlib.patches import Rectangle
from PIL import Image

from . import probcontour as P
from . import rsindices as RS

BG = "#0d0f13"
FG = "#e8e6e3"
plt.rcParams.update({
    "figure.facecolor": BG, "axes.facecolor": BG, "savefig.facecolor": BG,
    "text.color": FG, "axes.labelcolor": FG, "axes.edgecolor": "#3a3f4a",
    "xtick.color": FG, "ytick.color": FG, "font.size": 9,
    "axes.titlesize": 10, "figure.dpi": 110,
})


def _panel(ax, img, title, cmap=None, mask=None, lo=1.0, hi=99.0,
           subtitle=None):
    a = np.asarray(img, dtype=float)
    if a.ndim == 2:
        ref = a[mask] if mask is not None and mask.any() else a
        vmin, vmax = np.percentile(ref, [lo, hi])
        ax.imshow(a, cmap=cmap or "magma", vmin=vmin, vmax=vmax,
                  interpolation="bilinear")
    else:
        ax.imshow(np.clip(a, 0, 1), interpolation="bilinear")
    ax.set_title(title if subtitle is None else f"{title}\n{subtitle}",
                 color=FG, pad=6)
    ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values():
        s.set_color("#3a3f4a")
    return ax


def _focus(img: np.ndarray, hand_p: np.ndarray, floor: float = 0.16):
    """Dim everything outside the hand.

    The skin model is a model *of skin*. Applied to a plastered wall or a
    bookshelf it returns a number, but that number means nothing. Rather than
    crop -- which would hide how the segmentation behaved -- the background is
    attenuated by the hand posterior, so the frame stays readable as a scene
    while every quantitative panel visibly concentrates where the model applies.
    """
    w = floor + (1.0 - floor) * np.clip(hand_p, 0, 1)
    return img * (w[..., None] if np.ndim(img) == 3 else w)


def _save(fig, path: Path):
    fig.savefig(path, bbox_inches="tight", pad_inches=0.25)
    plt.close(fig)


def fig_overview(res, path: Path):
    f = res.fields
    fig, axes = plt.subplots(2, 3, figsize=(16, 11))
    _panel(axes[0, 0], res.rgb, "Source (EXIF-oriented, resampled)",
           subtitle=f"{res.rgb.shape[1]}x{res.rgb.shape[0]}")

    # quadtree overlay
    ax = axes[0, 1]
    ax.imshow(np.clip(res.rgb, 0, 1) ** 0.6, interpolation="bilinear")
    depths = np.array([t.depth for t in res.tiles])
    cmap = plt.get_cmap("viridis")
    dmin, dmax = depths.min(), max(depths.max(), depths.min() + 1)
    rects, colors = [], []
    for t in res.tiles:
        rects.append(Rectangle((t.x0, t.y0), t.x1 - t.x0, t.y1 - t.y0))
        colors.append(cmap((t.depth - dmin) / (dmax - dmin)))
    pc = PatchCollection(rects, facecolor="none", linewidths=0.45,
                         edgecolors=colors)
    ax.add_collection(pc)
    q = res.meta["quadtree"]
    _panel(ax, np.clip(res.rgb, 0, 1) ** 0.6,
           "Adaptive quadtree leaves (colour = depth)",
           subtitle=f"{q['n_leaves']} leaves, depth {q['depth_min']}-"
                    f"{q['depth_max']}, mean overlap x"
                    f"{q['mean_overlap_factor']:.2f}")

    _panel(axes[0, 2], f["lab"][..., 0], "CIELAB L*", cmap="gray",
           subtitle="lightness; the hand sits ~1 stop under the wall")

    _panel(axes[1, 0], f["hand_p"], "P(hand) — fused tiled MAP-EM posterior",
           cmap="cividis", lo=0, hi=100)
    ax = axes[1, 0]
    for lev, segs in P.contours(f["hand_p"], [0.25, 0.5, 0.75]).items():
        style = {0.25: (":", 0.8), 0.5: ("-", 1.6), 0.75: ("--", 0.8)}[lev]
        for s in segs:
            if len(s) > 40:
                ax.plot(s[:, 0], s[:, 1], style[0], lw=style[1],
                        color="#ff4d6d", alpha=0.9)

    _panel(axes[1, 1], f["tile_sep"],
           "Per-leaf class separation (fused)", cmap="inferno",
           subtitle="where the local mixture found two real classes")
    _panel(axes[1, 2], np.log10(np.maximum(f["shading"], 1e-4)),
           "Illumination / exposure field  log10", cmap="turbo",
           subtitle="observed luminance / model-predicted luminance")

    fig.suptitle("Stage 1 — CIELAB decomposition, overlapping quadtree, "
                 "probabilistic hand segmentation", color=FG, y=0.98,
                 fontsize=13)
    _save(fig, path)


def fig_chromophores(res, path: Path):
    f = res.fields
    m = f["hand_mask"]
    fig, axes = plt.subplots(1, 4, figsize=(20, 6))
    _panel(axes[0], f["c_mel"], "Melanosome volume fraction", cmap="copper",
           mask=m, subtitle="epidermal, from CIELAB chroma inversion")
    _panel(axes[1], f["c_blood"], "Blood volume fraction", cmap="RdPu_r",
           mask=m, subtitle="dermal whole-blood")
    _panel(axes[2], f["sto2"], "Modelled StO2", cmap="coolwarm_r", mask=m,
           lo=0, hi=100, subtitle="venous where blood is in smooth excess")
    _panel(axes[3], f["resid"], "Inversion residual (dE_ab)", cmap="viridis",
           mask=m, subtitle="colours the two-layer model cannot reach")
    fig.suptitle("Stage 2 — chromophore retrieval in the CIELAB chroma plane",
                 color=FG, y=1.01, fontsize=13)
    _save(fig, path)


def fig_bands(res, path: Path):
    f = res.fields
    m, hp = f["hand_mask"], f["hand_p"]
    fig, axes = plt.subplots(1, 4, figsize=(20, 6))
    from .spectra import VEIN_BANDS
    for ax, b in zip(axes, ["B760", "B850", "B940"]):
        c, fw, why = VEIN_BANDS[b]
        img = _focus(RS.percentile_stretch(f[b], res.tiles, mask=m), hp)
        _panel(ax, img, f"Synthetic {c:.0f} nm  (FWHM {fw:.0f} nm)",
               cmap="bone", lo=0, hi=100, subtitle=why)
    _panel(axes[3], _focus(f["false_color"], hp),
           "False-colour composite  R=940 G=850 B=760",
           subtitle="colour-infrared convention, per-tile 2-98% stretch")
    fig.suptitle("Stage 3 - forward-rendered vein-finder bands  "
                 "(background dimmed: the skin model only applies to skin)",
                 color=FG, y=1.01, fontsize=13)
    _save(fig, path)


def fig_indices(res, path: Path):
    f = res.fields
    m = f["hand_mask"]
    fig, axes = plt.subplots(2, 4, figsize=(20, 11))
    spec = [
        ("NDVI_vein", "NDVI_vein = (850−760)/(850+760)", "magma",
         "deoxy-Hb index; the vegetation-NDVI trick"),
        ("MAVI", "MAVI (SAVI form, L=0.5)", "magma",
         "melanin-adjusted vein index"),
        ("NDWI_tissue", "NDWI_tissue = (850−940)/(850+940)", "viridis",
         "940 nm water band"),
        ("SR", "Simple ratio 850/760", "cividis", "non-normalised contrast"),
        ("Brightness", "Tasseled cap 1 — Brightness", "gray",
         "scene albedo axis"),
        ("Vascularity", "Tasseled cap 2 — Vascularity", "magma",
         "850/760 contrast, orthogonal to brightness"),
        ("Hydration", "Tasseled cap 3 — Hydration", "viridis",
         "940 axis, orthogonal to both"),
        ("MNF1", "MNF 1 (highest SNR)", "bone", "noise-whitened PCA"),
    ]
    for ax, (k, title, cmap, sub) in zip(axes.ravel(), spec):
        a = f[k]
        ref = a[m] if m.any() else a
        vmin, vmax = np.percentile(ref, [1, 99])
        norm = np.clip((a - vmin) / max(vmax - vmin, 1e-9), 0, 1)
        _panel(ax, _focus(norm, f["hand_p"]), title, cmap=cmap, lo=0, hi=100,
               subtitle=sub)
    fig.suptitle("Stage 4 — remote-sensing band math on the synthetic stack",
                 color=FG, y=0.98, fontsize=13)
    _save(fig, path)


def fig_mnf(res, path: Path):
    f = res.fields
    m = f["hand_mask"]
    snr = res.meta["mnf_snr"]
    fig, axes = plt.subplots(1, 3, figsize=(16, 6))
    for i, ax in enumerate(axes):
        a = f[f"MNF{i+1}"]
        ref = a[m] if m.any() else a
        vmin, vmax = np.percentile(ref, [1, 99])
        a = _focus(np.clip((a - vmin) / max(vmax - vmin, 1e-9), 0, 1), f["hand_p"])
        _panel(ax, a, f"MNF component {i+1}", cmap="bone", lo=0, hi=100,
               subtitle=f"noise-whitened eigenvalue {snr[i]:.2f}"
                        f"{'  (≈1 ⇒ noise)' if snr[i] < 1.6 else ''}")
    fig.suptitle("Minimum Noise Fraction — components ordered by SNR, "
                 "not by variance", color=FG, y=1.01, fontsize=13)
    _save(fig, path)


def fig_veins(res, path: Path):
    f = res.fields
    m, hp, roi, sup = f["hand_mask"], f["hand_p"], f["roi"], f["support"]
    meta = res.meta
    fig, axes = plt.subplots(2, 3, figsize=(21, 13))

    vi = f["vein_index"]
    ref = vi[roi] if roi.any() else vi
    vmin, vmax = np.percentile(ref, [2, 98])
    _panel(axes[0, 0],
           _focus(np.clip((vi - vmin) / max(vmax - vmin, 1e-9), 0, 1), hp),
           "Vein index (MAVI)", cmap="magma", lo=0, hi=100,
           subtitle="melanin-adjusted 850/760 contrast")

    snr = f["dprime"]
    _panel(axes[0, 1], np.log10(np.maximum(snr, 1e-2)),
           "Detectability  log$_{10}$(d')", cmap="turbo", lo=1, hi=99,
           subtitle=f"d' = model vein contrast / propagated index noise; "
                    f"d'>={res.cfg.support_dprime:g} on "
                    f"{100*meta['support_fraction_of_roi']:.1f}% of the hand")
    ax = axes[0, 1]
    for sgm in P.contours(sup.astype(float), [0.5])[0.5]:
        if len(sgm) > 40:
            ax.plot(sgm[:, 0], sgm[:, 1], lw=1.0, color="#ffffff", alpha=0.8)

    _panel(axes[0, 2], f["vein_stat"] * roi,
           "Observed ridge response", cmap="inferno", lo=0, hi=99.5,
           subtitle="Frangi + crest gate, inside eroded interior")

    _panel(axes[1, 0], f["null_ridge"] * roi,
           "Null ridge response (surrogate frame)", cmap="inferno",
           lo=0, hi=99.5,
           subtitle=f"same noise, no structure: mean "
                    f"{meta['null_ridge_mean']:.4f} vs observed "
                    f"{meta['observed_ridge_mean']:.4f}")

    _panel(axes[1, 1], f["vein_post"], "P(vein | data), support-gated",
           cmap="inferno", lo=0, hi=100,
           subtitle="zero wherever the exposure cannot support a call")

    base = RS.percentile_stretch(f["B850"], res.tiles, mask=m)
    ax = axes[1, 2]
    ax.imshow(_focus(base, hp), cmap="bone", vmin=0, vmax=1,
              interpolation="bilinear")
    levels = [0.5, 0.7, 0.9]
    cols = ["#3fb8ff", "#39ff88", "#ffe066"]
    for (lev, segs), col in zip(P.contours(f["vein_post"], levels).items(), cols):
        for sgm in segs:
            if len(sgm) > 18:
                ax.plot(sgm[:, 0], sgm[:, 1], lw=1.0, color=col, alpha=0.9)
    for sgm in P.contours(sup.astype(float), [0.5])[0.5]:
        if len(sgm) > 40:
            ax.plot(sgm[:, 0], sgm[:, 1], lw=0.9, color="#ffffff", alpha=0.45)
    for sgm in P.contours(hp, [0.5])[0.5]:
        if len(sgm) > 60:
            ax.plot(sgm[:, 0], sgm[:, 1], lw=1.3, color="#ff4d6d", alpha=0.6)
    handles = [plt.Line2D([], [], color=c, lw=1.6, label=f"P(vein) = {l}")
               for l, c in zip(levels, cols)]
    handles += [plt.Line2D([], [], color="#ffffff", lw=1.4, alpha=0.6,
                           label="analysable support"),
                plt.Line2D([], [], color="#ff4d6d", lw=1.6,
                           label="P(hand) = 0.5")]
    ax.legend(handles=handles, loc="lower left", framealpha=0.4,
              facecolor="#11141a", edgecolor="#3a3f4a", fontsize=8)
    _panel(ax, _focus(base, hp),
           "Probabilistic vein contours over synthetic 850 nm", cmap="bone",
           lo=0, hi=100,
           subtitle=f"BH FDR q={res.cfg.fdr_q}: p<={meta['bh_p_threshold']:.2g}, "
                    f"{meta['vein_px']} px "
                    f"({100*meta['vein_fraction_of_support']:.1f}% of support)")
    fig.suptitle("Stage 5 - ridge detection against an empirical noise null, "
                 "gated by measurable support", color=FG, y=0.98, fontsize=13)
    _save(fig, path)


def fig_spectra(res, path: Path):
    """The physics the whole thing rests on."""
    from . import spectra as S
    from . import skin
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    lam = S.LAMBDA

    ax = axes[0]
    ax.semilogy(lam, S.MU_A_HBO2, color="#ff4d6d", label="HbO$_2$ (whole blood)")
    ax.semilogy(lam, S.MU_A_HB, color="#3fb8ff", label="Hb (whole blood)")
    ax.semilogy(lam, S.MU_A_MEL, color="#c98b3f", label="melanosome")
    ax.semilogy(lam, S.MU_A_H2O, color="#39ff88", label="water")
    for c, (cen, fw, _) in S.VEIN_BANDS.items():
        ax.axvspan(cen - fw / 2, cen + fw / 2, color="#ffffff", alpha=0.07)
        ax.text(cen, ax.get_ylim()[1] * 0.4, f"{cen:.0f}", ha="center",
                color=FG, fontsize=8)
    ax.axvline(800, color="#888", ls=":", lw=1)
    ax.text(802, 2e-2, "isosbestic 800 nm", color="#aaa", fontsize=7, rotation=90)
    ax.set_xlim(450, 1000); ax.set_ylim(1e-3, 1e3)
    ax.set_xlabel("wavelength (nm)"); ax.set_ylabel("$\\mu_a$ (cm$^{-1}$)")
    ax.set_title("Chromophore absorption")
    ax.legend(fontsize=7, framealpha=0.2, facecolor="#11141a", edgecolor="#3a3f4a")
    ax.grid(alpha=0.12)

    ax = axes[1]
    for sto2, col, lab_ in [(0.95, "#ff4d6d", "arterial StO$_2$=0.95"),
                            (0.55, "#3fb8ff", "venous StO$_2$=0.55")]:
        p = skin.SkinParams(np.array([0.10]), np.array([0.09]),
                            np.array([sto2]), np.array([0.65]))
        ax.plot(lam, skin.reflectance(p)[0], color=col, label=lab_)
    p = skin.SkinParams(np.array([0.10]), np.array([0.01]), np.array([0.75]),
                        np.array([0.65]))
    ax.plot(lam, skin.reflectance(p)[0], color="#aaa", ls="--",
            label="low blood (0.01)")
    for c, (cen, fw, _) in S.VEIN_BANDS.items():
        ax.axvspan(cen - fw / 2, cen + fw / 2, color="#fff", alpha=0.07)
    ax.set_xlim(450, 1000); ax.set_xlabel("wavelength (nm)")
    ax.set_ylabel("diffuse reflectance")
    ax.set_title("Modelled skin reflectance")
    ax.legend(fontsize=7, framealpha=0.2, facecolor="#11141a", edgecolor="#3a3f4a")
    ax.grid(alpha=0.12)

    ax = axes[2]
    lut = skin.SkinLUT(res.fields.get("_renderer") or __import__(
        "synthetic_nir.colorimetry", fromlist=["x"]).SpectralRenderer(
            res.cfg.cct_k), n_mel=28, n_blood=28)
    from .colorimetry import srgb_encode
    cols = np.clip(srgb_encode(lut.lin_rgb), 0, 1)
    ax.scatter(lut.lab[:, 1], lut.lab[:, 2], c=cols, s=14, edgecolors="none")
    m = res.fields["hand_mask"]
    if m.any():
        lab = res.fields["lab_denoised"][m]
        sel = np.random.default_rng(0).choice(len(lab), min(4000, len(lab)),
                                              replace=False)
        ax.scatter(lab[sel, 1], lab[sel, 2], s=1.5, c="#39ff88", alpha=0.25,
                   label="hand pixels")
        ax.legend(fontsize=7, framealpha=0.2, facecolor="#11141a",
                  edgecolor="#3a3f4a")
    ax.set_xlabel("a*"); ax.set_ylabel("b*")
    ax.set_title("Skin model locus in the CIELAB chroma plane")
    ax.grid(alpha=0.12)
    ax.set_aspect("equal", adjustable="box")

    fig.suptitle("Model basis — why 760 / 850 / 940 nm", color=FG, y=1.03,
                 fontsize=13)
    _save(fig, path)


def fig_validation(rows, frames, ph, roi, path: Path, real_lum_snr=None):
    """Positive control: the same detector on a phantom with known veins."""
    fig = plt.figure(figsize=(20, 10))
    gs = fig.add_gridspec(2, 4, height_ratios=[1.0, 1.0])

    bright = max(frames)
    ax = fig.add_subplot(gs[0, 0])
    _panel(ax, np.clip(frames[bright]["srgb"], 0, 1),
           f"Phantom rendered at exposure {bright:g}",
           subtitle=f"tissue mean code {rows[0]['tissue_code']:.0f}")
    ax = fig.add_subplot(gs[0, 1])
    _panel(ax, ph["vein"].astype(float), "Ground truth veins", cmap="gray",
           lo=0, hi=100, subtitle="known by construction")
    ax = fig.add_subplot(gs[0, 2])
    _panel(ax, frames[bright]["ridge"], "Ridge response", cmap="inferno",
           lo=0, hi=99.5, subtitle=f"AUC {rows[0]['auc']:.3f}")
    ax = fig.add_subplot(gs[0, 3])
    _panel(ax, frames[bright]["det"].astype(float),
           "Detections at FDR q=0.05", cmap="inferno", lo=0, hi=100,
           subtitle=f"recall {rows[0]['recall']:.2f}, "
                    f"precision {rows[0]['precision']:.3f}")

    ax = fig.add_subplot(gs[1, :2])
    codes = [r["tissue_code"] for r in rows]
    ax.plot(codes, [r["auc"] for r in rows], "o-", color="#39ff88", lw=2,
            label="ROC AUC")
    ax.plot(codes, [r["recall"] for r in rows], "s--", color="#3fb8ff",
            label="recall at FDR 0.05")
    ax.axhline(0.5, color="#888", ls=":", lw=1)
    ax.text(codes[-1], 0.52, "chance", color="#aaa", fontsize=8)
    ax.set_xscale("log")
    ax.set_xlabel("mean tissue code value (of 255)")
    ax.set_ylabel("score")
    ax.set_title("Detector performance vs exposure")
    ax.grid(alpha=0.15)
    ax.legend(fontsize=8, framealpha=0.2, facecolor="#11141a",
              edgecolor="#3a3f4a")
    ax.axvspan(0.5, 8.0, color="#ff4d6d", alpha=0.16)
    ax.text(2.0, 0.80, "where the real\nphotograph sits", color="#ff8fa3",
            fontsize=9, ha="center")

    ax = fig.add_subplot(gs[1, 2:])
    ax.plot(codes, [r["obs_ridge"] for r in rows], "o-", color="#ffe066",
            label="observed ridge response")
    ax.plot(codes, [r["null_ridge"] for r in rows], "s--", color="#ff4d6d",
            label="null (noise-only surrogate)")
    ax.set_xscale("log")
    ax.set_xlabel("mean tissue code value (of 255)")
    ax.set_ylabel("mean ridge response")
    ax.set_title("Signal vs the noise floor it must beat")
    ax.grid(alpha=0.15)
    ax.legend(fontsize=8, framealpha=0.2, facecolor="#11141a",
              edgecolor="#3a3f4a")

    fig.suptitle("Positive control - the identical detector on a phantom with "
                 "known veins", color=FG, y=0.98, fontsize=13)
    _save(fig, path)


def _write_png(a: np.ndarray, path: Path, cmap: str | None = None):
    a = np.asarray(a, float)
    if a.ndim == 2:
        if cmap:
            rgba = plt.get_cmap(cmap)(np.clip(a, 0, 1))
            arr = (rgba[..., :3] * 255).astype(np.uint8)
        else:
            arr = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    else:
        arr = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(arr).save(path)


def write_all(res, outdir: Path):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    fig_spectra(res, outdir / "00_model_basis.png")
    fig_overview(res, outdir / "01_overview.png")
    fig_chromophores(res, outdir / "02_chromophores.png")
    fig_bands(res, outdir / "03_nir_bands.png")
    fig_indices(res, outdir / "04_indices.png")
    fig_mnf(res, outdir / "05_mnf.png")
    fig_veins(res, outdir / "06_vein_contours.png")

    f, m = res.fields, res.fields["hand_mask"]
    bands = outdir / "bands"
    bands.mkdir(exist_ok=True)
    for b in ("B760", "B850", "B940"):
        _write_png(RS.percentile_stretch(f[b], res.tiles, mask=m),
                   bands / f"{b}.png")
    _write_png(f["false_color"], bands / "false_color_940_850_760.png")
    _write_png(RS.percentile_stretch(f["MAVI"], res.tiles, mask=m),
               bands / "MAVI.png", cmap="magma")
    _write_png(f["vein_post"], bands / "vein_posterior.png", cmap="inferno")
    _write_png(f["vein_stat"] * f["roi"], bands / "ridge_response.png",
               cmap="inferno")
    _write_png(f["support"].astype(float), bands / "support_mask.png")
    _write_png(f["hand_p"], bands / "hand_posterior.png", cmap="cividis")
