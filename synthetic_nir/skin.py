"""A two-layer skin optics model, and its inverse.

Forward
-------
Epidermis: a purely absorbing sheet of thickness d_epi carrying melanin.
           Attenuation is modified-Beer-Lambert with a diffuse path-length
           factor kappa (light crosses it twice, obliquely).
Dermis:    a semi-infinite turbid slab carrying whole blood, water and a
           bloodless baseline absorber, scattering per Jacques' power law.
           Its diffuse reflectance is the Kubelka-Munk infinite-thickness
           solution with the Star/van Gemert mapping from transport
           coefficients to KM's K and S.

    R(lambda) = T_epi(lambda)^2 * R_inf(lambda)

This is not Monte Carlo. It is the cheapest model that still reproduces the
three things the whole exercise depends on: melanin's steep lambda^-3.33 roll
-off into the NIR, the deoxy-Hb 758 nm band, and the oxy/deoxy crossover at
the 800 nm isosbestic point.

Inverse
-------
Three sRGB numbers cannot pin down melanin, blood, oxygenation *and* the local
illumination. So the inversion is done on shading-invariant colour: each pixel
is renormalised to a fixed luminance before being taken to CIELAB, which leaves
(a*, b*) as a pure chromaticity coordinate. A precomputed lookup table over
(melanin fraction, blood fraction) is matched in that plane with a KD-tree. The
luminance that was divided out is not thrown away -- it becomes the shading /
exposure field that the quadtree stage corrects.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.spatial import cKDTree

from . import spectra as S
from .colorimetry import SpectralRenderer, xyz_to_lab

# Geometry of the epidermal slab.
D_EPI_CM = 0.008          # 80 um
KAPPA = 2.2               # diffuse double-pass path-length factor


@dataclass
class SkinParams:
    """Volume fractions and oxygenation of one skin sample."""
    c_mel: np.ndarray      # melanosome volume fraction in epidermis
    c_blood: np.ndarray    # whole-blood volume fraction in dermis
    sto2: np.ndarray       # haemoglobin oxygen saturation, 0..1
    c_water: np.ndarray    # water volume fraction in dermis


def mu_a_dermis(c_blood, sto2, c_water) -> np.ndarray:
    """(..., n_lambda) dermal absorption coefficient, cm^-1."""
    c_blood = np.asarray(c_blood)[..., None]
    sto2 = np.asarray(sto2)[..., None]
    c_water = np.asarray(c_water)[..., None]
    mu_blood = sto2 * S.MU_A_HBO2 + (1.0 - sto2) * S.MU_A_HB
    return c_blood * mu_blood + c_water * S.MU_A_H2O + S.MU_A_BASE


def kubelka_munk_r_inf(mu_a: np.ndarray, mu_s_p: np.ndarray) -> np.ndarray:
    """Diffuse reflectance of a semi-infinite turbid slab.

    K = 2 mu_a and S = (3/4) mu_s' - mu_a/4 is the standard transport-to-KM
    mapping for a diffuse (not collimated) source.
    """
    K = 2.0 * mu_a
    Sc = np.maximum(0.75 * mu_s_p - 0.25 * mu_a, 1e-6)
    a = K / Sc
    return 1.0 + a - np.sqrt(a * a + 2.0 * a)


def transmittance_epidermis(c_mel: np.ndarray) -> np.ndarray:
    c_mel = np.asarray(c_mel)[..., None]
    mu_a_epi = c_mel * S.MU_A_MEL + (1.0 - c_mel) * S.MU_A_BASE
    return np.exp(-mu_a_epi * D_EPI_CM * KAPPA)


def reflectance(p: SkinParams) -> np.ndarray:
    """Full-spectrum diffuse reflectance, shape (..., n_lambda)."""
    t = transmittance_epidermis(p.c_mel)
    r_inf = kubelka_munk_r_inf(mu_a_dermis(p.c_blood, p.sto2, p.c_water), S.MU_S_P)
    return t * t * r_inf


def band_reflectance(refl: np.ndarray, band: str) -> np.ndarray:
    """Integrate a spectrum against one simulated LED emission profile."""
    return refl @ S.BAND_WEIGHTS[band]


# --- inversion ---------------------------------------------------------------

REF_Y = 0.45   # luminance every pixel is renormalised to before matching


def _chroma_lab(linear_rgb: np.ndarray, renderer: SpectralRenderer) -> np.ndarray:
    """Linear sRGB -> CIELAB after renormalising luminance to REF_Y.

    Dividing by Y removes any multiplicative illumination term exactly, so the
    returned (a*, b*) is a shading-invariant chromaticity. L* comes back as a
    constant and is discarded by the caller.
    """
    from .colorimetry import rgb_to_xyz
    xyz = rgb_to_xyz(linear_rgb)
    y = np.maximum(xyz[..., 1:2], 1e-9)
    return xyz_to_lab(xyz / y * REF_Y, renderer.white_xyz)


class SkinLUT:
    """Lookup table over (melanin, blood) matched in the CIELAB chroma plane."""

    def __init__(self, renderer: SpectralRenderer, n_mel: int = 112,
                 n_blood: int = 112, sto2: float = 0.70,
                 c_water: float = 0.65,
                 mel_range=(0.004, 0.45), blood_range=(0.0004, 0.14)):
        self.renderer = renderer
        self.sto2 = sto2
        self.c_water = c_water
        self.mel_grid = np.geomspace(*mel_range, n_mel)
        self.blood_grid = np.geomspace(*blood_range, n_blood)

        mm, bb = np.meshgrid(self.mel_grid, self.blood_grid, indexing="ij")
        self.mel_flat = mm.ravel()
        self.blood_flat = bb.ravel()

        p = SkinParams(self.mel_flat, self.blood_flat,
                       np.full_like(self.mel_flat, sto2),
                       np.full_like(self.mel_flat, c_water))
        self.refl = reflectance(p)                       # (n, n_lambda)
        self.lin_rgb = renderer.to_linear_rgb(self.refl)
        self.lab = renderer.to_lab(self.refl)
        self.chroma = _chroma_lab(self.lin_rgb, renderer)[..., 1:]   # (n, 2)
        self._tree = cKDTree(self.chroma)

    def invert(self, linear_rgb: np.ndarray, k: int = 4):
        """Match pixels to the table.

        Returns (c_mel, c_blood, residual_dE, shading) with the spatial shape of
        the input. `shading` is the ratio of observed luminance to the
        luminance the matched skin model predicts -- i.e. the illumination and
        exposure field, which is exactly what the quadtree stage corrects.
        """
        shape = linear_rgb.shape[:-1]
        flat = linear_rgb.reshape(-1, 3)
        chroma = _chroma_lab(flat, self.renderer)[..., 1:]

        dist, idx = self._tree.query(chroma, k=k, workers=-1)
        # Inverse-distance weighted blend of the k nearest table entries; this
        # softens the quantisation of the grid without smoothing spatially.
        w = 1.0 / np.maximum(dist, 1e-6)
        w /= w.sum(axis=1, keepdims=True)
        c_mel = (self.mel_flat[idx] * w).sum(axis=1)
        c_blood = (self.blood_flat[idx] * w).sum(axis=1)
        resid = dist[:, 0]

        from .colorimetry import rgb_to_xyz
        y_obs = rgb_to_xyz(flat)[..., 1]
        y_model = (rgb_to_xyz(self.lin_rgb)[..., 1][idx] * w).sum(axis=1)
        shading = y_obs / np.maximum(y_model, 1e-9)

        return (c_mel.reshape(shape), c_blood.reshape(shape),
                resid.reshape(shape), shading.reshape(shape))


# Per-band truncated wavelength grids. Each simulated LED is a narrow
# Gaussian, so integrating it against the full 380-1000 nm grid wastes ~85% of
# the work. Keeping only the samples carrying non-negligible weight makes the
# forward render of a multi-megapixel field practical.
_BAND_SUPPORT = {}
for _b, _w in S.BAND_WEIGHTS.items():
    _keep = np.nonzero(_w > 2e-4)[0]
    _BAND_SUPPORT[_b] = (
        _keep,
        (_w[_keep] / _w[_keep].sum()).astype(np.float32),
        S.MU_A_HBO2[_keep].astype(np.float32), S.MU_A_HB[_keep].astype(np.float32),
        S.MU_A_H2O[_keep].astype(np.float32), S.MU_A_MEL[_keep].astype(np.float32),
        S.MU_A_BASE[_keep].astype(np.float32), S.MU_S_P[_keep].astype(np.float32),
    )


def _band_reflectance_direct(c_mel, c_blood, sto2, c_water, band):
    """Reflectance in one band, evaluated only where that band has weight."""
    _, w, e_hbo2, e_hb, e_h2o, e_mel, e_base, mus = _BAND_SUPPORT[band]
    cm = c_mel[:, None]
    cb = c_blood[:, None]
    s = sto2[:, None]
    cw = c_water[:, None]

    mu_a_epi = cm * e_mel + (1.0 - cm) * e_base
    t = np.exp(-mu_a_epi * D_EPI_CM * KAPPA)

    mu_a = cb * (s * e_hbo2 + (1.0 - s) * e_hb) + cw * e_h2o + e_base
    r_inf = kubelka_munk_r_inf(mu_a, mus)
    return (t * t * r_inf) @ w


def synthesize_nir(c_mel, c_blood, sto2, c_water, bands=("B760", "B850", "B940")):
    """Forward-render the recovered chromophore fields into NIR bands.

    Shapes are preserved. Work is chunked over pixels and truncated over
    wavelength, so peak memory stays bounded regardless of image size.
    """
    shape = np.shape(c_mel)
    flat = [np.asarray(v, dtype=np.float32).ravel()
            for v in (c_mel, c_blood, sto2, c_water)]
    n = flat[0].size
    out = {b: np.empty(n, dtype=np.float32) for b in bands}
    chunk = 1 << 19
    for i in range(0, n, chunk):
        sl = slice(i, min(i + chunk, n))
        args = [v[sl] for v in flat]
        for b in bands:
            out[b][sl] = _band_reflectance_direct(*args, b)
    return {b: v.reshape(shape) for b, v in out.items()}


def reference_vein_contrast(c_mel: float = 0.11, c_water: float = 0.65,
                            blood_bg: float = 0.020, blood_vein: float = 0.090,
                            sto2_bg: float = 0.90, sto2_vein: float = 0.55,
                            L: float = 0.5) -> float:
    """Vein index contrast a canonical vessel produces, from the forward model.

    This is the *signal* half of a detectability index: how far the melanin-
    adjusted vein index moves between background dermis and a subpapillary vein
    at the same pigmentation. Paired with the propagated noise on that index it
    says whether a vessel could be seen at a given exposure at all -- which is a
    far more meaningful support criterion than a raw code-value SNR, since
    well-exposed saturated skin legitimately has a small blue channel.
    """
    def mavi_of(blood, sto2):
        p = SkinParams(np.array([c_mel]), np.array([blood]),
                       np.array([sto2]), np.array([c_water]))
        r = reflectance(p)
        b760 = band_reflectance(r, "B760")[0]
        b850 = band_reflectance(r, "B850")[0]
        return (1.0 + L) * (b850 - b760) / (b850 + b760 + L)

    return float(abs(mavi_of(blood_vein, sto2_vein) - mavi_of(blood_bg, sto2_bg)))
