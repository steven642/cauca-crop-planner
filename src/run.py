"""Uso:
  python -m src.run --sintetico
  python -m src.run --clima data/power_diario.csv --celdas data/celdas.csv
Genera dos conjuntos de resultados en salidas/:
  reciente/       -> ultimos meses OBSERVADOS (que paso)
  planificacion/  -> proximos 12 meses con clima PROMEDIO historico por dia (que se podria sembrar)
celdas.csv: celda_id,lat,lon,elev,dist_rio_m,nodo_lat,nodo_lon"""
import argparse
import copy
import json
import os
import pandas as pd
import yaml
from .suitability import evaluar
from . import sintetico

CRIT = ["T2M", "T2M_MAX", "T2M_MIN", "PRECTOTCORR", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN"]


def cargar_clima(ruta):
    d = pd.read_csv(ruta, parse_dates=["fecha"]).drop_duplicates(["lat", "lon", "fecha"], keep="last")
    out = {}
    for (la, lo), g in d.groupby(["lat", "lon"]):
        g = g.sort_values("fecha").reset_index(drop=True)
        ok = g[CRIT].notna().all(axis=1)
        if ok.any():                       # recorta el final si POWER aun no publica alguna variable
            g = g.loc[: ok[ok].index.max()]
        out[(la, lo)] = g.interpolate(limit=3)
    return out


def guardar(salida, modo, quinc, fichas, cfg):
    d = os.path.join(salida, modo)
    os.makedirs(d, exist_ok=True)
    tols = list(fichas)
    base = cfg["regla_permanencia"]["tolerancia"]
    f0 = fichas[min(tols, key=lambda t: abs(t - base))]
    quinc["aptitud"] = quinc["aptitud"].round(3)
    quinc.to_csv(os.path.join(d, "aptitud_quincenal.csv.gz"), index=False)
    f0.to_json(os.path.join(d, "fichas.json"), orient="records", force_ascii=False)
    resumen = {str(t): {"fichas": len(f), "celdas_con_ficha": int(f["celda"].nunique()) if len(f) else 0,
                        "por_especie": f["especie"].value_counts().to_dict() if len(f) else {}} for t, f in fichas.items()}
    json.dump(resumen, open(os.path.join(d, "sensibilidad.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(f"[{modo}]")
    for t, v in resumen.items():
        print("  tolerancia", t, "->", v["fichas"], "fichas en", v["celdas_con_ficha"], "celdas")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--sintetico", action="store_true")
    ap.add_argument("--clima")
    ap.add_argument("--celdas")
    ap.add_argument("--cultivos", default="data/cultivos_base.csv")
    ap.add_argument("--salida", default="salidas")
    a = ap.parse_args()
    cfg = yaml.safe_load(open(a.config, encoding="utf-8"))
    cultivos = pd.read_csv(a.cultivos)
    if a.sintetico:
        clima = {0: sintetico.clima_sintetico(anios=3)}
        celdas = pd.DataFrame({"celda_id": ["alta", "media", "baja"], "lat": 2.4, "lon": -76.6,
                               "elev": [2900, 2200, 1700], "dist_rio_m": [2000, 300, 100], "nodo_id": 0})
    else:
        clima = cargar_clima(a.clima)
        celdas = pd.read_csv(a.celdas)
        celdas["nodo_id"] = list(zip(celdas["nodo_lat"], celdas["nodo_lon"]))
    tols = cfg["regla_permanencia"]["sensibilidad"]
    for modo in ("reciente", "climatologia"):
        c2 = copy.deepcopy(cfg)
        c2["linea_tiempo"]["modo"] = modo
        quinc, fichas = evaluar(clima, celdas, cultivos, c2, tolerancias=tols)
        guardar(a.salida, "reciente" if modo == "reciente" else "planificacion", quinc, fichas, c2)


if __name__ == "__main__":
    main()
