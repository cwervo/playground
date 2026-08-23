"""Spectral primitives: CIE colour-matching functions, illuminants, and the
chromophore absorption spectra used by the skin forward model.

Wavelengths are in nanometres, absorption coefficients in cm^-1.

Sources
-------
CIE 1931 CMFs   Wyman, Sloan & Shirley (2013), "Simple Analytic Approximations
                to the CIE XYZ Color Matching Functions", JCGT 2(2). Multi-lobe
                piecewise-Gaussian fits; accurate to ~1% of peak.
Haemoglobin     Prahl's compilation of Gratzer / Kollias molar extinction data
                (cm^-1 / (mol/L)). Tabulated below at the wavelengths that carry
                the features this model depends on: the Soret shoulder, the
                visible Q-bands, the 500/529/545/570 isosbestic points, the
                758 nm deoxy-Hb band, the 800 nm NIR isosbestic point, and the
                HbO2 > Hb crossover above it.
Water           Hale & Querry (1973) pure-water absorption; the weak 760 nm
                band and the strong 970 nm band are what matter here.
Melanin, base   Jacques (1998, 2013) power laws.
Scattering      Jacques (2013), "Optical properties of biological tissues: a
                review": mu_s' = a (lambda/500)^-b, skin a = 45.3, b = 1.29.

Below 450 nm the haemoglobin table is coarse. This is deliberate and harmless:
whole blood is effectively opaque through the Soret band, so skin colour there
is set by melanin and scattering, not by the exact epsilon.
"""

from __future__ import annotations

import numpy as np

# --- sampling grid -----------------------------------------------------------

LAMBDA_MIN, LAMBDA_MAX, LAMBDA_STEP = 380.0, 1000.0, 2.0
LAMBDA = np.arange(LAMBDA_MIN, LAMBDA_MAX + LAMBDA_STEP, LAMBDA_STEP)
VIS = (LAMBDA >= 380.0) & (LAMBDA <= 780.0)


# --- CIE 1931 colour matching functions --------------------------------------

def _piecewise_gauss(x: np.ndarray, alpha: float, mu: float,
                     sigma_lo: float, sigma_hi: float) -> np.ndarray:
    sigma = np.where(x < mu, sigma_lo, sigma_hi)
    t = (x - mu) / sigma
    return alpha * np.exp(-0.5 * t * t)


def cie_xyz_bar(lam: np.ndarray) -> np.ndarray:
    """CIE 1931 2-degree observer, shape (n, 3). Wyman et al. analytic fit."""
    g = _piecewise_gauss
    x = (g(lam, 1.056, 599.8, 37.9, 31.0)
         + g(lam, 0.362, 442.0, 16.0, 26.7)
         + g(lam, -0.065, 501.1, 20.4, 26.2))
    y = (g(lam, 0.821, 568.8, 46.9, 40.5)
         + g(lam, 0.286, 530.9, 16.3, 31.1))
    z = (g(lam, 1.217, 437.0, 11.8, 36.0)
         + g(lam, 0.681, 459.0, 26.0, 13.8))
    out = np.stack([x, y, z], axis=-1)
    # The fit is only defined across the visible band.
    out[(lam < 380.0) | (lam > 780.0)] = 0.0
    return np.clip(out, 0.0, None)


XYZ_BAR = cie_xyz_bar(LAMBDA)


def planck(lam: np.ndarray, cct_k: float) -> np.ndarray:
    """Planckian (blackbody) spectral radiance, peak-normalised.

    Used as a stand-in for the scene illuminant. A window-lit interior is not a
    blackbody, but a Planckian of the right correlated colour temperature gets
    the red/blue balance close enough that the chromaticity inversion is not
    systematically tilted.
    """
    lam_m = lam * 1e-9
    c1, c2 = 3.7418e-16, 1.4388e-2
    with np.errstate(over="ignore"):
        rad = c1 / (lam_m ** 5 * (np.exp(c2 / (lam_m * cct_k)) - 1.0))
    return rad / rad.max()


# --- haemoglobin -------------------------------------------------------------
# lambda, epsilon_HbO2, epsilon_Hb   [cm^-1 / (mol/L)]
_HB_TABLE = np.array([
    [380.0, 180000.0, 160000.0],
    [400.0, 266232.0, 223296.0],
    [420.0, 442000.0, 320000.0],
    [440.0, 234000.0, 260000.0],
    [450.0,  62816.0,  76510.0],
    [460.0,  36000.0,  49000.0],
    [480.0,  22000.0,  27000.0],
    [500.0,  20862.0,  20862.0],
    [520.0,  39036.0,  39036.0],
    [540.0,  53236.0,  53412.0],
    [545.0,  50600.0,  50600.0],
    [550.0,  43016.0,  53788.0],
    [555.0,  40000.0,  54540.0],
    [560.0,  32610.0,  53100.0],
    [570.0,  44496.0,  44496.0],
    [576.0,  62640.0,  37020.0],
    [580.0,  50104.0,  33210.0],
    [590.0,  14400.0,  19000.0],
    [600.0,   3200.0,  14677.0],
    [620.0,   1130.0,   8182.0],
    [640.0,    442.0,   4551.0],
    [650.0,    368.0,   3750.0],
    [660.0,    320.0,   3227.0],
    [680.0,    295.0,   2189.0],
    [700.0,    290.0,   1794.0],
    [730.0,    390.0,   3200.0],
    [740.0,    478.0,   4000.0],
    [758.0,   1160.0,   4750.0],
    [760.0,   1214.0,   4712.0],
    [780.0,    980.0,   3200.0],
    [800.0,    816.0,    816.0],
    [820.0,    900.0,    740.0],
    [850.0,   1058.0,    691.0],
    [880.0,   1150.0,    720.0],
    [900.0,   1198.0,    726.0],
    [920.0,   1210.0,    700.0],
    [940.0,   1214.0,    693.0],
    [970.0,   1180.0,    690.0],
    [1000.0,  1100.0,    690.0],
])

# lambda, mu_a of pure water [cm^-1]  (Hale & Querry 1973)
_WATER_TABLE = np.array([
    [380.0, 0.00120], [400.0, 0.00058], [450.0, 0.00025], [500.0, 0.00025],
    [550.0, 0.00064], [600.0, 0.00230], [650.0, 0.00340], [700.0, 0.00600],
    [740.0, 0.02600], [760.0, 0.02600], [780.0, 0.02400], [800.0, 0.02000],
    [820.0, 0.02500], [850.0, 0.04300], [880.0, 0.05500], [900.0, 0.06800],
    [920.0, 0.11000], [940.0, 0.27000], [960.0, 0.40000], [970.0, 0.45000],
    [980.0, 0.42000], [1000.0, 0.36000],
])

HB_G_PER_L = 150.0          # haemoglobin in whole blood
HB_MW = 64500.0             # g/mol


def _interp(table: np.ndarray, col: int) -> np.ndarray:
    return np.interp(LAMBDA, table[:, 0], table[:, col])


def mu_a_hbo2() -> np.ndarray:
    """Absorption of *whole oxygenated blood*, cm^-1."""
    return 2.303 * _interp(_HB_TABLE, 1) * HB_G_PER_L / HB_MW


def mu_a_hb() -> np.ndarray:
    """Absorption of *whole deoxygenated blood*, cm^-1."""
    return 2.303 * _interp(_HB_TABLE, 2) * HB_G_PER_L / HB_MW


def mu_a_water() -> np.ndarray:
    return _interp(_WATER_TABLE, 1)


def mu_a_melanosome() -> np.ndarray:
    """Jacques' melanosome power law, cm^-1."""
    return 6.6e11 * LAMBDA ** -3.33


def mu_a_baseline() -> np.ndarray:
    """Bloodless, melanin-free soft tissue background, cm^-1."""
    return 7.84e8 * LAMBDA ** -3.255


def mu_s_prime(a: float = 45.3, b: float = 1.29) -> np.ndarray:
    """Reduced scattering coefficient of skin, cm^-1."""
    return a * (LAMBDA / 500.0) ** -b


MU_A_HBO2 = mu_a_hbo2()
MU_A_HB = mu_a_hb()
MU_A_H2O = mu_a_water()
MU_A_MEL = mu_a_melanosome()
MU_A_BASE = mu_a_baseline()
MU_S_P = mu_s_prime()


# --- simulated vein-finder emitters -----------------------------------------

VEIN_BANDS = {
    # name: (centre nm, FWHM nm, what it is for)
    "B760": (760.0, 30.0, "deoxy-Hb absorption band; venous blood goes dark"),
    "B850": (850.0, 35.0, "above the 800 nm isosbestic; dermal backscatter reference"),
    "B940": (940.0, 40.0, "water band; deepest penetration, hydration contrast"),
}


def band_weights(centre: float, fwhm: float) -> np.ndarray:
    """Normalised Gaussian emission profile of one simulated LED."""
    sigma = fwhm / 2.3548200450309493
    w = np.exp(-0.5 * ((LAMBDA - centre) / sigma) ** 2)
    return w / w.sum()


BAND_WEIGHTS = {k: band_weights(c, f) for k, (c, f, _) in VEIN_BANDS.items()}
