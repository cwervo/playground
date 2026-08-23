"""Invariants for the pipeline. Run: python -m synthetic_nir.tests"""

from __future__ import annotations

import numpy as np
from scipy import ndimage

from . import colorimetry as C
from . import probcontour as P
from . import quadtree as Q
from . import rsindices as RS
from . import skin
from . import spectra as S
from . import vessel

FAILURES = []


def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    print(f"  [{status}] {name}" + (f"  {detail}" if detail else ""))
    if not cond:
        FAILURES.append(name)


def test_colorimetry():
    print("colorimetry")
    rgb = np.array([[0.5, 0.3, 0.25], [1.0, 1.0, 1.0], [0.0, 0.0, 0.0]])
    back = C.lab_to_srgb(C.srgb_to_lab(rgb))
    check("sRGB->Lab->sRGB round-trips", np.abs(back - rgb).max() < 1e-6,
          f"max err {np.abs(back - rgb).max():.2e}")
    check("white maps to L*=100", abs(C.srgb_to_lab(np.array([1.0, 1, 1]))[0] - 100) < 1e-4)
    r = C.SpectralRenderer(6500)
    lab = r.to_lab(np.ones_like(S.LAMBDA))
    check("perfect reflector is neutral L*=100",
          abs(lab[0] - 100) < 1e-6 and abs(lab[1]) < 1e-6 and abs(lab[2]) < 1e-6)


def test_spectra():
    print("spectra / skin optics")
    i = lambda l: int(np.argmin(abs(S.LAMBDA - l)))
    check("deoxy-Hb absorbs more at 760 nm",
          S.MU_A_HB[i(760)] > 3 * S.MU_A_HBO2[i(760)],
          f"{S.MU_A_HB[i(760)]:.1f} vs {S.MU_A_HBO2[i(760)]:.1f} cm^-1")
    check("800 nm is isosbestic",
          abs(S.MU_A_HB[i(800)] - S.MU_A_HBO2[i(800)]) < 0.2)
    check("ordering reverses above 800 nm",
          S.MU_A_HBO2[i(850)] > S.MU_A_HB[i(850)])
    check("melanin falls steeply into the NIR",
          S.MU_A_MEL[i(550)] / S.MU_A_MEL[i(760)] > 2.5,
          f"{S.MU_A_MEL[i(550)] / S.MU_A_MEL[i(760)]:.2f}x from 550 to 760 nm")
    check("water peaks near 940 nm",
          S.MU_A_H2O[i(940)] > 5 * S.MU_A_H2O[i(850)])

    r = C.SpectralRenderer(6500)
    p = skin.SkinParams(np.array([0.02]), np.array([0.01]), np.array([0.7]),
                        np.array([0.65]))
    lab = r.to_lab(skin.reflectance(p))[0]
    check("light skin renders to plausible CIELAB",
          55 < lab[0] < 85 and 0 < lab[1] < 20 and 10 < lab[2] < 40,
          f"L*={lab[0]:.1f} a*={lab[1]:.1f} b*={lab[2]:.1f}")

    def mavi_at(bl, s):
        pp = skin.SkinParams(np.array([0.10]), np.array([bl]), np.array([s]),
                             np.array([0.65]))
        rf = skin.reflectance(pp)
        return RS.mavi(skin.band_reflectance(rf, "B760")[0],
                       skin.band_reflectance(rf, "B850")[0])

    check("vein index rises with deoxygenation",
          mavi_at(0.09, 0.55) > mavi_at(0.09, 0.95))
    check("vein index rises with blood volume when venous",
          mavi_at(0.09, 0.55) > mavi_at(0.02, 0.55))
    check("pigmentation reduces vein contrast",
          skin.reference_vein_contrast(c_mel=0.30)
          < skin.reference_vein_contrast(c_mel=0.03))


def test_quadtree():
    print("quadtree")
    rng = np.random.default_rng(0)
    g = np.zeros((512, 512)); g[:, :256] = 0.8
    g[300:, 300:] += rng.normal(0, 0.05, (212, 212))
    tiles = Q.build(g, min_size=16, max_depth=6, detail_thresh=0.02, presmooth=0)
    m = Q.Mosaic(g.shape)
    for t in tiles:
        m.add(t, np.ones(t.halo_shape))
    w = m.result()
    check("feather weights form a partition of unity",
          np.abs(w - 1.0).max() < 1e-9, f"max dev {np.abs(w - 1).max():.2e}")
    out = Q.process(g, tiles, lambda sub, t: sub)
    check("identity reconstruction is exact",
          np.abs(out - g).max() < 1e-12, f"max err {np.abs(out - g).max():.2e}")
    st = Q.stats(tiles, g.shape)
    check("cores tile the image exactly once", abs(st["core_coverage"] - 1) < 1e-9)
    check("tiles genuinely overlap", st["mean_overlap_factor"] > 1.5,
          f"x{st['mean_overlap_factor']:.2f}")
    check("subdivision is adaptive", st["depth_max"] > st["depth_min"])


def test_fdr():
    print("Benjamini-Hochberg")
    rng = np.random.default_rng(2)
    n, frac, amp = 65536, 0.12, 3.0
    z = rng.normal(0, 1, n); k = int(n * frac); z[:k] += amp
    p = P.norm_sf(z); thr = P.bh_threshold(p, 0.05); flag = p <= thr
    fdr = flag[k:].sum() / max(flag.sum(), 1)
    check("empirical FDR is controlled at q", fdr <= 0.05 + 0.01,
          f"{fdr:.3f} vs target 0.05")
    check("power is reasonable", flag[:k].sum() / k > 0.4,
          f"recall {flag[:k].sum() / k:.2f}")
    # Under the *complete* null, BH rejects something with probability exactly
    # q -- so "never rejects" is the wrong assertion (an earlier version of this
    # test made it and duly failed 1 run in 20). The property to check is the
    # rate across replicates.
    reps, q = 60, 0.05
    any_rej = sum(P.bh_threshold(P.norm_sf(rng.normal(0, 1, 20000)), q) > 0
                  for _ in range(reps))
    check("family-wise rejection rate under a pure null matches q",
          any_rej <= reps * q + 3 * np.sqrt(reps * q * (1 - q)),
          f"{any_rej}/{reps} replicates rejected anything (expect ~{reps * q:.0f})")


def test_vesselness():
    print("ridge detection")
    h = w = 300
    img = np.zeros((h, w)); img[:, :120] = 1.0
    yy, xx = np.mgrid[0:h, 0:w]
    ridge = np.exp(-((xx - 200 - 15 * np.sin(yy / 25)) ** 2) / (2 * 2.5 ** 2))
    img = img + 0.5 * ridge + np.random.default_rng(0).normal(0, 0.02, (h, w))
    rm, em = ridge > 0.5, np.abs(xx - 120) < 4
    v_off, _ = vessel.vesselness(img, crest_gate=False)
    v_on, _ = vessel.vesselness(img, crest_gate=True, gamma=0.35)
    s_off = v_off[rm].mean() / max(v_off[em].mean(), 1e-12)
    s_on = v_on[rm].mean() / max(v_on[em].mean(), 1e-12)
    check("crest gate improves ridge-over-edge selectivity", s_on > 4 * s_off,
          f"{s_off:.1f}x -> {s_on:.1f}x")
    check("ridge still responds strongly", v_on[rm].mean() > 0.25,
          f"{v_on[rm].mean():.3f}")


def test_transforms():
    print("remote-sensing transforms")
    rng = np.random.default_rng(0)
    h = w = 128
    b = {"B760": 0.35 + rng.normal(0, 0.01, (h, w)),
         "B850": 0.45 + rng.normal(0, 0.01, (h, w)),
         "B940": 0.48 + rng.normal(0, 0.01, (h, w))}
    b["B760"][40:80, 40:80] -= 0.06
    tc, R, _ = RS.tasseled_cap(b)
    check("tasseled-cap basis is orthonormal",
          np.abs(R @ R.T - np.eye(R.shape[0])).max() < 1e-9)
    check("vascularity axis separates the vein patch",
          tc["Vascularity"][50:70, 50:70].mean() > tc["Vascularity"][:20, :20].mean())
    comps, snr, _ = RS.mnf(b)
    check("MNF orders by SNR, noise components near unity",
          snr[0] > 3 * snr[1] and snr[1] < 2.0,
          f"eigenvalues {np.round(snr, 2).tolist()}")


def test_nir_fast_path():
    print("NIR synthesis")
    rng = np.random.default_rng(0); n = 4000
    cm = rng.uniform(0.01, 0.3, n); cb = rng.uniform(0.001, 0.1, n)
    st = rng.uniform(0.5, 0.95, n); cw = np.full(n, 0.65)
    fast = skin.synthesize_nir(cm, cb, st, cw)
    ref = skin.reflectance(skin.SkinParams(cm, cb, st, cw))
    worst = max(np.abs(skin.band_reflectance(ref, k) - fast[k]).max()
                / skin.band_reflectance(ref, k).mean() for k in fast)
    check("truncated-band path matches full-spectrum integration",
          worst < 1e-3, f"max rel err {worst:.2e}")


def main():
    for t in (test_colorimetry, test_spectra, test_quadtree, test_fdr,
              test_vesselness, test_transforms, test_nir_fast_path):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED: {FAILURES}")
        raise SystemExit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
