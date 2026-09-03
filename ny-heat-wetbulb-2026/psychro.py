"""
Psychrometrics for heat-health analysis.

Wet-bulb temperature via Stull (2011), J. Appl. Meteor. Climatol. 50(11):2267-2269
  "Wet-Bulb Temperature from Relative Humidity and Air Temperature"
  Valid: T -20..50 C, RH 5..99 %. RMS error ~0.3 C.

Relative humidity from dew point via the Magnus-Tetens approximation.
Heat index via the NWS Rothfusz regression (with the two standard adjustments),
inverted numerically to recover RH when only T and HI are reported.
"""
import math

def f_to_c(f): return (f - 32.0) * 5.0 / 9.0
def c_to_f(c): return c * 9.0 / 5.0 + 32.0

def sat_vapor_pressure(t_c):
    """Magnus: saturation vapour pressure in hPa."""
    return 6.112 * math.exp(17.67 * t_c / (t_c + 243.5))

def rh_from_dewpoint(t_c, td_c):
    """Relative humidity (%) from air temp and dew point, both Celsius."""
    return 100.0 * sat_vapor_pressure(td_c) / sat_vapor_pressure(t_c)

def dewpoint_from_rh(t_c, rh):
    """Inverse of the above: dew point (C) from air temp (C) and RH (%)."""
    gamma = math.log(max(rh, 1e-9) / 100.0) + 17.67 * t_c / (t_c + 243.5)
    return 243.5 * gamma / (17.67 - gamma)

def wet_bulb_stull(t_c, rh):
    """Stull (2011) wet-bulb temperature in Celsius. t_c in C, rh in percent."""
    rh = min(max(rh, 0.5), 100.0)
    return (t_c * math.atan(0.151977 * math.sqrt(rh + 8.313659))
            + math.atan(t_c + rh)
            - math.atan(rh - 1.676331)
            + 0.00391838 * rh ** 1.5 * math.atan(0.023101 * rh)
            - 4.686035)

def wet_bulb_depression(t_c, rh):
    """T_air - T_wet-bulb, in Celsius degrees.

    This is the evaporative-cooling headroom. It goes to zero at saturation:
    when it is small, sweat cannot evaporate and the body loses its main
    avenue of heat loss regardless of how high the air temperature is.
    """
    return t_c - wet_bulb_stull(t_c, rh)

def heat_index_f(t_f, rh):
    """NWS Rothfusz heat index in F, with the standard low- and high-RH adjustments."""
    simple = 0.5 * (t_f + 61.0 + (t_f - 68.0) * 1.2 + rh * 0.094)
    if (simple + t_f) / 2.0 < 80.0:
        return simple
    hi = (-42.379 + 2.04901523 * t_f + 10.14333127 * rh
          - 0.22475541 * t_f * rh - 0.00683783 * t_f * t_f
          - 0.05481717 * rh * rh + 0.00122874 * t_f * t_f * rh
          + 0.00085282 * t_f * rh * rh - 0.00000199 * t_f * t_f * rh * rh)
    if rh < 13.0 and 80.0 <= t_f <= 112.0:
        hi -= ((13.0 - rh) / 4.0) * math.sqrt((17.0 - abs(t_f - 95.0)) / 17.0)
    elif rh > 85.0 and 80.0 <= t_f <= 87.0:
        hi += ((rh - 85.0) / 10.0) * ((87.0 - t_f) / 5.0)
    return hi

def rh_from_heat_index(t_f, target_hi_f):
    """Recover RH (%) from a reported air temperature and heat index (bisection).

    Returns None when the target heat index is unreachable at that air
    temperature -- the caller must not silently substitute a guess.
    """
    lo, hi_rh = 1.0, 100.0
    if heat_index_f(t_f, hi_rh) < target_hi_f or heat_index_f(t_f, lo) > target_hi_f:
        return None
    for _ in range(200):
        mid = 0.5 * (lo + hi_rh)
        if heat_index_f(t_f, mid) < target_hi_f:
            lo = mid
        else:
            hi_rh = mid
    return 0.5 * (lo + hi_rh)
