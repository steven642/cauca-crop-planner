"""ETo FAO-56 Penman-Monteith (diario), grados-dia y funciones de aptitud."""
import numpy as np
import pandas as pd


def _es(t):
    return 0.6108 * np.exp(17.27 * t / (t + 237.3))


def radiacion_extraterrestre(lat_deg, doy):
    phi = np.radians(lat_deg)
    dr = 1 + 0.033 * np.cos(2 * np.pi * doy / 365)
    d = 0.409 * np.sin(2 * np.pi * doy / 365 - 1.39)
    ws = np.arccos(np.clip(-np.tan(phi) * np.tan(d), -1, 1))
    return (24 * 60 / np.pi) * 0.0820 * dr * (ws * np.sin(phi) * np.sin(d) + np.cos(phi) * np.cos(d) * np.sin(ws))


def eto_pm(tmean, tmax, tmin, rh, u2, rs, lat, elev, doy):
    """Todos arrays; rs en MJ/m2/dia; u2 en m/s."""
    P = 101.3 * ((293 - 0.0065 * elev) / 293) ** 5.26
    gamma = 0.000665 * P
    delta = 4098 * _es(tmean) / (tmean + 237.3) ** 2
    es = (_es(tmax) + _es(tmin)) / 2
    ea = es * rh / 100
    ra = radiacion_extraterrestre(lat, doy)
    rso = (0.75 + 2e-5 * elev) * ra
    rns = 0.77 * rs
    ratio = np.clip(rs / np.maximum(rso, 1e-6), 0.3, 1.0)
    sigma = 4.903e-9
    rnl = sigma * ((tmax + 273.16) ** 4 + (tmin + 273.16) ** 4) / 2 * (0.34 - 0.14 * np.sqrt(ea)) * (1.35 * ratio - 0.35)
    rn = rns - rnl
    num = 0.408 * delta * rn + gamma * 900 / (tmean + 273) * u2 * (es - ea)
    den = delta + gamma * (1 + 0.34 * u2)
    return np.maximum(num / den, 0)


def gdd_diario(tmean, t_base, t_techo=30.0):
    return np.clip(np.minimum(tmean, t_techo) - t_base, 0, None)


def trapecio(t, tmin, topt_min, topt_max, tmax):
    """Puntaje 0-1 de temperatura: 0 fuera de [tmin,tmax], 1 en el óptimo."""
    s = np.zeros_like(t, dtype=float)
    up = (t > tmin) & (t < topt_min)
    s[up] = (t[up] - tmin) / (topt_min - tmin)
    s[(t >= topt_min) & (t <= topt_max)] = 1.0
    dn = (t > topt_max) & (t < tmax)
    s[dn] = (tmax - t[dn]) / (tmax - topt_max)
    return s
