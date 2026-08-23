"""sRGB <-> CIEXYZ <-> CIELAB, and spectrum -> CIELAB rendering.

Everything downstream does its statistics in CIELAB because the two chroma axes
are (a) very nearly independent of illumination *level*, which this photograph
badly needs, and (b) perceptually uniform enough that a Euclidean distance in
(a*, b*) is a defensible cost function for the chromophore inversion.
"""

from __future__ import annotations

import numpy as np

from . import spectra as S

# sRGB / Rec.709 primaries, D65 white.
M_XYZ_FROM_RGB = np.array([
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041],
])
M_RGB_FROM_XYZ = np.linalg.inv(M_XYZ_FROM_RGB)

D65 = np.array([0.95047, 1.00000, 1.08883])


def srgb_decode(u: np.ndarray) -> np.ndarray:
    """Gamma-encoded sRGB in [0,1] -> linear light."""
    u = np.clip(u, 0.0, 1.0)
    return np.where(u <= 0.04045, u / 12.92, ((u + 0.055) / 1.055) ** 2.4)


def srgb_encode(v: np.ndarray) -> np.ndarray:
    v = np.clip(v, 0.0, 1.0)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * v ** (1 / 2.4) - 0.055)


def rgb_to_xyz(rgb: np.ndarray) -> np.ndarray:
    return rgb @ M_XYZ_FROM_RGB.T


def xyz_to_rgb(xyz: np.ndarray) -> np.ndarray:
    return xyz @ M_RGB_FROM_XYZ.T


def _f(t: np.ndarray) -> np.ndarray:
    d = 6.0 / 29.0
    return np.where(t > d ** 3, np.cbrt(np.maximum(t, 1e-12)),
                    t / (3 * d * d) + 4.0 / 29.0)


def _f_inv(t: np.ndarray) -> np.ndarray:
    d = 6.0 / 29.0
    return np.where(t > d, t ** 3, 3 * d * d * (t - 4.0 / 29.0))


def xyz_to_lab(xyz: np.ndarray, white: np.ndarray = D65) -> np.ndarray:
    fx, fy, fz = [_f(xyz[..., i] / white[i]) for i in range(3)]
    return np.stack([116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)], axis=-1)


def lab_to_xyz(lab: np.ndarray, white: np.ndarray = D65) -> np.ndarray:
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200
    return np.stack([_f_inv(fx) * white[0], _f_inv(fy) * white[1],
                     _f_inv(fz) * white[2]], axis=-1)


def srgb_to_lab(u: np.ndarray) -> np.ndarray:
    return xyz_to_lab(rgb_to_xyz(srgb_decode(u)))


def lab_to_srgb(lab: np.ndarray) -> np.ndarray:
    return srgb_encode(xyz_to_rgb(lab_to_xyz(lab)))


def lab_to_lch(lab: np.ndarray) -> np.ndarray:
    """L*, C*_ab, h_ab (degrees in [0, 360))."""
    c = np.hypot(lab[..., 1], lab[..., 2])
    h = np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) % 360.0
    return np.stack([lab[..., 0], c, h], axis=-1)


class SpectralRenderer:
    """Renders reflectance spectra to linear sRGB / CIELAB under one illuminant."""

    def __init__(self, cct_k: float = 6500.0):
        self.cct_k = cct_k
        self.spd = S.planck(S.LAMBDA, cct_k)
        # Integration weights: illuminant x CMF x wavelength step.
        self._w = self.spd[:, None] * S.XYZ_BAR * S.LAMBDA_STEP
        # Normalise so that a perfect diffuse reflector renders to Y = 1.
        self._k = 1.0 / (self.spd * S.XYZ_BAR[:, 1] * S.LAMBDA_STEP).sum()
        self.white_xyz = self._k * self._w.sum(axis=0)

    def to_xyz(self, refl: np.ndarray) -> np.ndarray:
        """refl: (..., n_lambda) reflectance -> (..., 3) XYZ."""
        return self._k * (refl @ self._w)

    def to_lab(self, refl: np.ndarray) -> np.ndarray:
        return xyz_to_lab(self.to_xyz(refl), self.white_xyz)

    def to_linear_rgb(self, refl: np.ndarray) -> np.ndarray:
        # Adapt from the scene white to D65 by simple von Kries scaling in XYZ.
        xyz = self.to_xyz(refl) * (D65 / self.white_xyz)
        return xyz_to_rgb(xyz)
