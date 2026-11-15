"""Descarga/actualiza NASA POWER de forma incremental.
  python -m src.actualizar            # crea o actualiza data/power_diario.csv
POWER publica meteorologia con ~2-3 dias de retraso y radiacion con ~5-7; ademas los ultimos dias
se revisan despues, por eso cada actualizacion vuelve a bajar los ultimos 60 dias (solape)."""
import argparse
import os
from datetime import datetime, timezone
import pandas as pd
import yaml
from .power_client import descargar_nodo, nodos_region


def actualizar(cfg, ruta, solape_dias=60):
    p = cfg["power"]
    hoy = datetime.now(timezone.utc).strftime("%Y%m%d")
    viejo = None
    inicio = str(p["inicio"])
    if os.path.exists(ruta):
        viejo = pd.read_csv(ruta, parse_dates=["fecha"])
        inicio = (viejo["fecha"].max() - pd.Timedelta(days=solape_dias)).strftime("%Y%m%d")
    nuevos = []
    for lat, lon in nodos_region(cfg):
        print("nodo", lat, lon, "desde", inicio, "hasta", hoy)
        nuevos.append(descargar_nodo(lat, lon, p["parametros"], inicio, hoy, p["comunidad"]))
    nuevo = pd.concat(nuevos)
    if viejo is not None:
        corte = pd.to_datetime(inicio, format="%Y%m%d")
        nuevo = pd.concat([viejo[viejo["fecha"] < corte], nuevo])
    nuevo = nuevo.drop_duplicates(["lat", "lon", "fecha"], keep="last").sort_values(["lat", "lon", "fecha"])
    nuevo.to_csv(ruta, index=False)
    print("guardado", ruta, len(nuevo), "filas; ultimo dia:", nuevo["fecha"].max().date())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--salida", default="data/power_diario.csv")
    a = ap.parse_args()
    actualizar(yaml.safe_load(open(a.config, encoding="utf-8")), a.salida)
