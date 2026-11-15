"""Descarga diaria de NASA POWER por nodo. Requiere internet (correr en tu PC)."""
import time
import numpy as np
import pandas as pd
import requests

URL = "https://power.larc.nasa.gov/api/temporal/daily/point"


def descargar_nodo(lat, lon, params, inicio, fin, comunidad="AG", reintentos=3):
    q = {"parameters": ",".join(params), "community": comunidad, "longitude": lon,
         "latitude": lat, "start": inicio, "end": fin, "format": "JSON"}
    for i in range(reintentos):
        try:
            r = requests.get(URL, params=q, timeout=120)
            r.raise_for_status()
            j = r.json()
            break
        except Exception:
            if i == reintentos - 1:
                raise
            time.sleep(5 * (i + 1))
    par = j["properties"]["parameter"]
    elev = j["geometry"]["coordinates"][2]
    df = pd.DataFrame(par)
    df.index = pd.to_datetime(df.index, format="%Y%m%d")
    df = df.replace(-999, np.nan)
    df["lat"], df["lon"], df["elev_power"] = lat, lon, elev
    return df.rename_axis("fecha").reset_index()


def nodos_region(cfg):
    r, p = cfg["region"], cfg["power"]
    lats = np.arange(r["lat_min"], r["lat_max"] + 1e-9, p["nodo_paso_lat"])
    lons = np.arange(r["lon_min"], r["lon_max"] + 1e-9, p["nodo_paso_lon"])
    return [(round(a, 3), round(b, 3)) for a in lats for b in lons]


def descargar_region(cfg, salida):
    p = cfg["power"]
    out = []
    for lat, lon in nodos_region(cfg):
        print("nodo", lat, lon)
        out.append(descargar_nodo(lat, lon, p["parametros"], p["inicio"], p["fin"], p["comunidad"]))
    pd.concat(out).to_csv(salida, index=False)
    print("guardado", salida)
