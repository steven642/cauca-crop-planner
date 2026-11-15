"""Datos sintéticos SOLO para probar el flujo sin internet. No usar en resultados reales."""
import numpy as np
import pandas as pd


def clima_sintetico(lat=2.4, lon=-76.6, elev_power=2200, anios=3, semilla=0):
    rng = np.random.default_rng(semilla)
    f = pd.date_range("2020-01-01", periods=365 * anios, freq="D")
    doy = f.dayofyear.values
    tm = 14 + 1.0 * np.sin(2 * np.pi * (doy - 60) / 365) + rng.normal(0, 0.8, len(f))
    lluvia_s = 0.5 + 0.5 * np.cos(2 * np.pi * (doy - 300) / 182)   # dos épocas lluviosas
    p = rng.gamma(0.6, 8 * lluvia_s + 0.5)
    return pd.DataFrame({"fecha": f, "T2M": tm, "T2M_MAX": tm + 5, "T2M_MIN": tm - 5,
                         "PRECTOTCORR": p, "RH2M": 80 + rng.normal(0, 4, len(f)),
                         "WS2M": 2 + rng.random(len(f)), "ALLSKY_SFC_SW_DWN": 16 + rng.normal(0, 3, len(f)),
                         "lat": lat, "lon": lon, "elev_power": elev_power})
