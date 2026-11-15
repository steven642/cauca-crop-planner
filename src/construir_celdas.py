"""Construye data/celdas.csv desde un DEM y (opcional) una capa de rios.
  python -m src.construir_celdas --dem data/dem.tif --rios data/rios.shp
Requiere: rasterio, geopandas. DEM en EPSG:4326 (Copernicus/SRTM lo estan)."""
import argparse
import numpy as np
import pandas as pd
import yaml
import rasterio
import geopandas as gpd
from pyproj import Transformer
from .power_client import nodos_region

UTM = "EPSG:32618"   # UTM 18N cubre lon -78 a -72 (Alto Cauca)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--dem", required=True)
    ap.add_argument("--rios")
    ap.add_argument("--paso-m", type=float, default=1000)
    ap.add_argument("--salida", default="data/celdas.csv")
    a = ap.parse_args()
    cfg = yaml.safe_load(open(a.config, encoding="utf-8"))
    r = cfg["region"]
    to_utm = Transformer.from_crs("EPSG:4326", UTM, always_xy=True)
    to_ll = Transformer.from_crs(UTM, "EPSG:4326", always_xy=True)
    x0, y0 = to_utm.transform(r["lon_min"], r["lat_min"])
    x1, y1 = to_utm.transform(r["lon_max"], r["lat_max"])
    xs, ys = np.meshgrid(np.arange(x0, x1, a.paso_m) + a.paso_m / 2, np.arange(y0, y1, a.paso_m) + a.paso_m / 2)
    lon, lat = to_ll.transform(xs.ravel(), ys.ravel())
    df = pd.DataFrame({"lat": lat, "lon": lon, "x": xs.ravel(), "y": ys.ravel()})
    with rasterio.open(a.dem) as src:
        nd = src.nodata
        df["elev"] = [v[0] for v in src.sample(zip(df["lon"], df["lat"]))]
        if nd is not None:
            df.loc[df["elev"] == nd, "elev"] = np.nan
    df = df[df["elev"].notna() & (df["elev"] > 0)].copy()
    if a.rios:
        rios = gpd.read_file(a.rios, bbox=(r["lon_min"] - .1, r["lat_min"] - .1, r["lon_max"] + .1, r["lat_max"] + .1))
        if len(rios):
            rios = rios.to_crs(UTM)
            pts = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df["x"], df["y"]), crs=UTM)
            lineas = rios.geometry.union_all() if hasattr(rios.geometry, "union_all") else rios.geometry.unary_union
            df["dist_rio_m"] = pts.geometry.distance(lineas).values
        else:
            print("AVISO: no hay rios dentro del recuadro; dist_rio_m = 1e9")
            df["dist_rio_m"] = 1e9
    else:
        print("AVISO: sin capa de rios; dist_rio_m = 1e9")
        df["dist_rio_m"] = 1e9
    nodos = np.array(nodos_region(cfg))
    cosl = np.cos(np.radians(df["lat"].mean()))
    d = ((df["lat"].values[:, None] - nodos[:, 0]) ** 2 + ((df["lon"].values[:, None] - nodos[:, 1]) * cosl) ** 2)
    k = d.argmin(axis=1)
    df["nodo_lat"], df["nodo_lon"] = nodos[k, 0], nodos[k, 1]
    df.insert(0, "celda_id", [f"c{i:05d}" for i in range(len(df))])
    df[["celda_id", "lat", "lon", "elev", "dist_rio_m", "nodo_lat", "nodo_lon"]].round(4).to_csv(a.salida, index=False)
    print("celdas:", len(df), "->", a.salida)


if __name__ == "__main__":
    main()
