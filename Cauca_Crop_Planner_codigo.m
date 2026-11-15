% CAUCA CROP PLANNER - complete project code (NASA Space Apps 2026)
% Read-only file: the original Python code of each module, commented line by line,
% so it can be read in the MATLAB editor. It does not run in MATLAB; the app runs in Python.


%% ===== FILE: config.yaml =====
%  # Región: Alto Cauca - Macizo Colombiano (aprox.). Ajustar tras confirmar polígono de la cuenca.
%  region:
%    nombre: "Alto Cauca - Macizo Colombiano"
%    lat_min: 2.0
%    lat_max: 2.8
%    lon_min: -76.9
%    lon_max: -76.2
%  power:
%    # NASA POWER (MERRA-2) tiene celdas de ~0.5 x 0.625 grados: se descargan nodos y se corrige por altitud.
%    nodo_paso_lat: 0.5
%    nodo_paso_lon: 0.625
%    inicio: 19810101
%    fin: 20251231
%    parametros: [T2M, T2M_MAX, T2M_MIN, PRECTOTCORR, RH2M, WS2M, ALLSKY_SFC_SW_DWN]
%    comunidad: AG
%  correccion:
%    gradiente_termico_c_por_m: -0.0065   # estándar; calibrar con estaciones IDEAM
%    factor_precip: 1.0                   # calibrar con estaciones IDEAM
%  linea_tiempo:
%    paso: quincenal          # 1-15 y 16-fin de mes
%    meses: 6                 # meses que se muestran en la linea de tiempo (mapa/slider)
%    fichas_meses: 12         # meses que se usan para evaluar las fichas (cultivos de ciclo largo)
%    modo: reciente           # reciente = ultimos 6 meses observados; climatologia = proximos 6 meses con promedio historico por dia del año
%    fin: auto                # auto = ultimo dia con datos completos de NASA POWER
%  aptitud:
%    combinacion: minimo      # ley del minimo (como Ecocrop); alternativa: producto
%    umbral_diario: 0.6
%    ventana_agua_dias: 30
%    distancia_rio_riego_m: 500           # dentro de esta distancia se asume agua complementaria
%    aporte_riego_mm_ventana: 40
%  regla_permanencia:
%    tolerancia: 0.05                     # +-5 %, sobre grados-dia (ver memoria sec. 4)
%    sensibilidad: [0.025, 0.05, 0.10]

%% ===== FILE: src/power_client.py =====
%  """Descarga diaria de NASA POWER por nodo. Requiere internet (correr en tu PC)."""
%  import time
%  import numpy as np
%  import pandas as pd
%  import requests
%
%  URL = "https://power.larc.nasa.gov/api/temporal/daily/point"
%
%
%  def descargar_nodo(lat, lon, params, inicio, fin, comunidad="AG", reintentos=3):
%      q = {"parameters": ",".join(params), "community": comunidad, "longitude": lon,
%           "latitude": lat, "start": inicio, "end": fin, "format": "JSON"}
%      for i in range(reintentos):
%          try:
%              r = requests.get(URL, params=q, timeout=120)
%              r.raise_for_status()
%              j = r.json()
%              break
%          except Exception:
%              if i == reintentos - 1:
%                  raise
%              time.sleep(5 * (i + 1))
%      par = j["properties"]["parameter"]
%      elev = j["geometry"]["coordinates"][2]
%      df = pd.DataFrame(par)
%      df.index = pd.to_datetime(df.index, format="%Y%m%d")
%      df = df.replace(-999, np.nan)
%      df["lat"], df["lon"], df["elev_power"] = lat, lon, elev
%      return df.rename_axis("fecha").reset_index()
%
%
%  def nodos_region(cfg):
%      r, p = cfg["region"], cfg["power"]
%      lats = np.arange(r["lat_min"], r["lat_max"] + 1e-9, p["nodo_paso_lat"])
%      lons = np.arange(r["lon_min"], r["lon_max"] + 1e-9, p["nodo_paso_lon"])
%      return [(round(a, 3), round(b, 3)) for a in lats for b in lons]
%
%
%  def descargar_region(cfg, salida):
%      p = cfg["power"]
%      out = []
%      for lat, lon in nodos_region(cfg):
%          print("nodo", lat, lon)
%          out.append(descargar_nodo(lat, lon, p["parametros"], p["inicio"], p["fin"], p["comunidad"]))
%      pd.concat(out).to_csv(salida, index=False)
%      print("guardado", salida)

%% ===== FILE: src/construir_celdas.py =====
%  """Construye data/celdas.csv desde un DEM y (opcional) una capa de rios.
%    python -m src.construir_celdas --dem data/dem.tif --rios data/rios.shp
%  Requiere: rasterio, geopandas. DEM en EPSG:4326 (Copernicus/SRTM lo estan)."""
%  import argparse
%  import numpy as np
%  import pandas as pd
%  import yaml
%  import rasterio
%  import geopandas as gpd
%  from pyproj import Transformer
%  from .power_client import nodos_region
%
%  UTM = "EPSG:32618"   # UTM 18N cubre lon -78 a -72 (Alto Cauca)
%
%
%  def main():
%      ap = argparse.ArgumentParser()
%      ap.add_argument("--config", default="config.yaml")
%      ap.add_argument("--dem", required=True)
%      ap.add_argument("--rios")
%      ap.add_argument("--paso-m", type=float, default=1000)
%      ap.add_argument("--salida", default="data/celdas.csv")
%      a = ap.parse_args()
%      cfg = yaml.safe_load(open(a.config, encoding="utf-8"))
%      r = cfg["region"]
%      to_utm = Transformer.from_crs("EPSG:4326", UTM, always_xy=True)
%      to_ll = Transformer.from_crs(UTM, "EPSG:4326", always_xy=True)
%      x0, y0 = to_utm.transform(r["lon_min"], r["lat_min"])
%      x1, y1 = to_utm.transform(r["lon_max"], r["lat_max"])
%      xs, ys = np.meshgrid(np.arange(x0, x1, a.paso_m) + a.paso_m / 2, np.arange(y0, y1, a.paso_m) + a.paso_m / 2)
%      lon, lat = to_ll.transform(xs.ravel(), ys.ravel())
%      df = pd.DataFrame({"lat": lat, "lon": lon, "x": xs.ravel(), "y": ys.ravel()})
%      with rasterio.open(a.dem) as src:
%          nd = src.nodata
%          df["elev"] = [v[0] for v in src.sample(zip(df["lon"], df["lat"]))]
%          if nd is not None:
%              df.loc[df["elev"] == nd, "elev"] = np.nan
%      df = df[df["elev"].notna() & (df["elev"] > 0)].copy()
%      if a.rios:
%          rios = gpd.read_file(a.rios, bbox=(r["lon_min"] - .1, r["lat_min"] - .1, r["lon_max"] + .1, r["lat_max"] + .1))
%          if len(rios):
%              rios = rios.to_crs(UTM)
%              pts = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df["x"], df["y"]), crs=UTM)
%              lineas = rios.geometry.union_all() if hasattr(rios.geometry, "union_all") else rios.geometry.unary_union
%              df["dist_rio_m"] = pts.geometry.distance(lineas).values
%          else:
%              print("AVISO: no hay rios dentro del recuadro; dist_rio_m = 1e9")
%              df["dist_rio_m"] = 1e9
%      else:
%          print("AVISO: sin capa de rios; dist_rio_m = 1e9")
%          df["dist_rio_m"] = 1e9
%      nodos = np.array(nodos_region(cfg))
%      cosl = np.cos(np.radians(df["lat"].mean()))
%      d = ((df["lat"].values[:, None] - nodos[:, 0]) ** 2 + ((df["lon"].values[:, None] - nodos[:, 1]) * cosl) ** 2)
%      k = d.argmin(axis=1)
%      df["nodo_lat"], df["nodo_lon"] = nodos[k, 0], nodos[k, 1]
%      df.insert(0, "celda_id", [f"c{i:05d}" for i in range(len(df))])
%      df[["celda_id", "lat", "lon", "elev", "dist_rio_m", "nodo_lat", "nodo_lon"]].round(4).to_csv(a.salida, index=False)
%      print("celdas:", len(df), "->", a.salida)
%
%
%  if __name__ == "__main__":
%      main()

%% ===== FILE: src/agro.py =====
%  """ETo FAO-56 Penman-Monteith (diario), grados-dia y funciones de aptitud."""
%  import numpy as np
%  import pandas as pd
%
%
%  def _es(t):
%      return 0.6108 * np.exp(17.27 * t / (t + 237.3))
%
%
%  def radiacion_extraterrestre(lat_deg, doy):
%      phi = np.radians(lat_deg)
%      dr = 1 + 0.033 * np.cos(2 * np.pi * doy / 365)
%      d = 0.409 * np.sin(2 * np.pi * doy / 365 - 1.39)
%      ws = np.arccos(np.clip(-np.tan(phi) * np.tan(d), -1, 1))
%      return (24 * 60 / np.pi) * 0.0820 * dr * (ws * np.sin(phi) * np.sin(d) + np.cos(phi) * np.cos(d) * np.sin(ws))
%
%
%  def eto_pm(tmean, tmax, tmin, rh, u2, rs, lat, elev, doy):
%      """Todos arrays; rs en MJ/m2/dia; u2 en m/s."""
%      P = 101.3 * ((293 - 0.0065 * elev) / 293) ** 5.26
%      gamma = 0.000665 * P
%      delta = 4098 * _es(tmean) / (tmean + 237.3) ** 2
%      es = (_es(tmax) + _es(tmin)) / 2
%      ea = es * rh / 100
%      ra = radiacion_extraterrestre(lat, doy)
%      rso = (0.75 + 2e-5 * elev) * ra
%      rns = 0.77 * rs
%      ratio = np.clip(rs / np.maximum(rso, 1e-6), 0.3, 1.0)
%      sigma = 4.903e-9
%      rnl = sigma * ((tmax + 273.16) ** 4 + (tmin + 273.16) ** 4) / 2 * (0.34 - 0.14 * np.sqrt(ea)) * (1.35 * ratio - 0.35)
%      rn = rns - rnl
%      num = 0.408 * delta * rn + gamma * 900 / (tmean + 273) * u2 * (es - ea)
%      den = delta + gamma * (1 + 0.34 * u2)
%      return np.maximum(num / den, 0)
%
%
%  def gdd_diario(tmean, t_base, t_techo=30.0):
%      return np.clip(np.minimum(tmean, t_techo) - t_base, 0, None)
%
%
%  def trapecio(t, tmin, topt_min, topt_max, tmax):
%      """Puntaje 0-1 de temperatura: 0 fuera de [tmin,tmax], 1 en el óptimo."""
%      s = np.zeros_like(t, dtype=float)
%      up = (t > tmin) & (t < topt_min)
%      s[up] = (t[up] - tmin) / (topt_min - tmin)
%      s[(t >= topt_min) & (t <= topt_max)] = 1.0
%      dn = (t > topt_max) & (t < tmax)
%      s[dn] = (tmax - t[dn]) / (tmax - topt_max)
%      return s

%% ===== FILE: src/suitability.py =====
%  """Aptitud diaria por celda y cultivo + regla de permanencia (tolerancia sobre grados-dia)
%  + linea de tiempo quincenal sobre una ventana de N meses."""
%  import numpy as np
%  import pandas as pd
%  from .agro import eto_pm, gdd_diario, trapecio
%
%
%  def preparar_celda(clima, celda, cfg):
%      """Corrige un nodo POWER a una celda (altitud, precip) y calcula ETo."""
%      c = clima.copy()
%      dz = celda["elev"] - c["elev_power"].iloc[0]
%      g = cfg["correccion"]["gradiente_termico_c_por_m"]
%      for v in ("T2M", "T2M_MAX", "T2M_MIN"):
%          c[v] = c[v] + g * dz
%      c["PRECTOTCORR"] = c["PRECTOTCORR"] * cfg["correccion"]["factor_precip"]
%      doy = c["fecha"].dt.dayofyear.values
%      c["ETO"] = eto_pm(c["T2M"].values, c["T2M_MAX"].values, c["T2M_MIN"].values,
%                        c["RH2M"].values, c["WS2M"].values, c["ALLSKY_SFC_SW_DWN"].values,
%                        celda["lat"], celda["elev"], doy)
%      return c
%
%
%  def ventana_tiempo(c, cfg, meses=None):
%      """Devuelve (serie_a_usar, inicio, fin) segun el modo de la linea de tiempo."""
%      lt = cfg["linea_tiempo"]
%      meses = meses or lt["meses"]
%      w = cfg["aptitud"]["ventana_agua_dias"]
%      ult = c["fecha"].max()
%      if lt["modo"] == "climatologia":
%          inicio = ult + pd.Timedelta(days=1)
%          fin = inicio + pd.DateOffset(months=meses) - pd.Timedelta(days=1)
%          fechas = pd.date_range(inicio, fin, freq="D")
%          cols = ["T2M", "T2M_MAX", "T2M_MIN", "PRECTOTCORR", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN", "ETO"]
%          clim = c.assign(doy=c["fecha"].dt.dayofyear.clip(upper=365)).groupby("doy")[cols].mean()
%          fut = clim.reindex(np.minimum(fechas.dayofyear.values, 365)).reset_index(drop=True)
%          fut.insert(0, "fecha", fechas)
%          previo = c.tail(w)[["fecha"] + cols]
%          return pd.concat([previo, fut], ignore_index=True), inicio, fin
%      fin = ult if lt["fin"] == "auto" else pd.Timestamp(lt["fin"])
%      inicio = fin - pd.DateOffset(months=meses) + pd.Timedelta(days=1)
%      return c[c["fecha"] <= fin].reset_index(drop=True), inicio, fin
%
%
%  def apto_diario(c, cultivo, celda, cfg):
%      a = cfg["aptitud"]
%      w = a["ventana_agua_dias"]
%      ts = trapecio(c["T2M"].values, cultivo["t_min"], cultivo["t_opt_min"], cultivo["t_opt_max"], cultivo["t_max"])
%      etc = (c["ETO"] * cultivo["kc_medio"]).rolling(w, min_periods=w // 2).sum()
%      oferta = c["PRECTOTCORR"].rolling(w, min_periods=w // 2).sum()
%      if celda.get("dist_rio_m", 1e9) <= a["distancia_rio_riego_m"]:
%          oferta = oferta + a["aporte_riego_mm_ventana"]
%      ws = np.clip(oferta / etc.replace(0, np.nan), 0, 1).fillna(0).values
%      score = np.minimum(ts, ws) if a.get("combinacion", "minimo") == "minimo" else ts * ws
%      return score, score >= a["umbral_diario"]
%
%
%  def fichas_permanencia(c, apto, cultivo, tolerancia, score=None):
%      """Tramos continuos aptos cuyo GDD acumulado >= gdd_ciclo*(1-tol).
%      Devuelve ventana de siembra, dias estimados hasta cosecha y ventana de cosecha."""
%      gdd = gdd_diario(c["T2M"].values, cultivo["t_base_gdd"])
%      meta = cultivo["gdd_ciclo"] * (1 - tolerancia)
%      fechas = c["fecha"].values
%      res, n, i = [], len(apto), 0
%      while i < n:
%          if not apto[i]:
%              i += 1
%              continue
%          j = i
%          while j < n and apto[j]:
%              j += 1
%          tramo = gdd[i:j]
%          acum_rev = np.cumsum(tramo[::-1])[::-1]   # GDD disponibles si siembra el dia k del tramo
%          ok = np.where(acum_rev >= meta)[0]
%          if len(ok):
%              k0, k1 = int(ok[0]), int(ok[-1])
%
%              def dur(k):                            # dias necesarios desde la siembra k hasta acumular la meta
%                  return int(np.searchsorted(np.cumsum(tramo[k:]), meta) + 1)
%              d0, d1 = dur(k0), dur(k1)
%              res.append({"siembra_desde": str(fechas[i + k0])[:10], "siembra_hasta": str(fechas[i + k1])[:10],
%                          "dias_a_cosecha_desde": d0, "dias_a_cosecha_hasta": d1,
%                          "cosecha_desde": str(fechas[i + k0 + d0 - 1])[:10],
%                          "cosecha_hasta": str(fechas[i + k1 + d1 - 1])[:10],
%                          "dias_tramo": int(j - i), "gdd_tramo": round(float(tramo.sum()), 1),
%                          "aptitud_media_tramo": round(float(np.mean(score[i:j])), 3) if score is not None else None})
%          i = j
%      return res
%
%
%  def quincena_inicio(fechas):
%      f = pd.Series(pd.to_datetime(fechas))
%      return f.dt.to_period("M").dt.start_time + pd.to_timedelta((f.dt.day > 15) * 15, unit="D")
%
%
%  def recortar(clima, cfg):
%      """Recorta la serie larga de un nodo a lo que realmente se usa (acelera con miles de celdas)."""
%      lt, w = cfg["linea_tiempo"], cfg["aptitud"]["ventana_agua_dias"]
%      ult = clima["fecha"].max()
%      if lt["modo"] == "climatologia":
%          return clima[clima["fecha"] >= ult - pd.DateOffset(years=20)].reset_index(drop=True)
%      fin = ult if lt["fin"] == "auto" else pd.Timestamp(lt["fin"])
%      ini = fin - pd.DateOffset(months=max(lt["meses"], lt.get("fichas_meses", lt["meses"]))) - pd.Timedelta(days=w + 5)
%      return clima[clima["fecha"] >= ini].reset_index(drop=True)
%
%
%  def evaluar(clima_por_nodo, celdas, cultivos, cfg, tolerancias=None):
%      """Devuelve (quincenal_df, {tolerancia: fichas_df}). Linea de tiempo = lt['meses']; fichas = lt['fichas_meses']."""
%      tols = tolerancias or [cfg["regla_permanencia"]["tolerancia"]]
%      lt = cfg["linea_tiempo"]
%      m_vis, m_fic = lt["meses"], lt.get("fichas_meses", lt["meses"])
%      clima_por_nodo = {k: recortar(v, cfg) for k, v in clima_por_nodo.items()}
%      quinc, fichas = [], {t: [] for t in tols}
%      for _, celda in celdas.iterrows():
%          c0 = preparar_celda(clima_por_nodo[celda["nodo_id"]], celda, cfg)
%          c, ini_f, fin_f = ventana_tiempo(c0, cfg, meses=m_fic)
%          if lt["modo"] == "climatologia":
%              ini_v, fin_v = ini_f, ini_f + pd.DateOffset(months=m_vis) - pd.Timedelta(days=1)
%          else:
%              fin_v, ini_v = fin_f, fin_f - pd.DateOffset(months=m_vis) + pd.Timedelta(days=1)
%          mf = ((c["fecha"] >= ini_f) & (c["fecha"] <= fin_f)).values
%          mv = ((c["fecha"] >= ini_v) & (c["fecha"] <= fin_v)).values
%          cf = c[mf].reset_index(drop=True)
%          qk = quincena_inicio(c[mv]["fecha"]).values
%          for _, cult in cultivos.iterrows():
%              score, apto = apto_diario(c, cult, celda, cfg)
%              q = pd.Series(score[mv]).groupby(qk).mean()
%              for f, v in q.items():
%                  quinc.append({"celda": celda["celda_id"], "especie": cult["especie"], "quincena": f, "aptitud": float(v)})
%              for t in tols:
%                  for v in fichas_permanencia(cf, apto[mf], cult, t, score[mf]):
%                      borde = pd.Timestamp(v["siembra_desde"]) <= ini_f + pd.Timedelta(days=2)
%                      fichas[t].append({"celda": celda["celda_id"], "especie": cult["especie"],
%                                        "familia": cult["familia"], "fija_nitrogeno": cult["fija_nitrogeno"],
%                                        "ciclo_dias": int(cult["ciclo_dias"]), "tolerancia": t,
%                                        "modo": lt["modo"], "ventana_meses": m_fic,
%                                        "empieza_en_borde": bool(borde), **v})
%      return pd.DataFrame(quinc), {t: pd.DataFrame(f) for t, f in fichas.items()}

%% ===== FILE: src/rotacion.py =====
%  """Rotaciones recomendadas por sector.
%  1) mejores_rotaciones(): optimizador por reglas (siempre funciona, sin internet ni clave).
%  2) explicar_con_ia(): opcional, redacta/explica con un modelo si hay ANTHROPIC_API_KEY.
%  Las reglas y pesos son criterio de diseno (inspirado en principios de rotacion: alternar familias,
%  incluir leguminosas, no repetir solanaceas) y deben validarse con un agronomo."""
%  import itertools
%  import json
%  import os
%  import pandas as pd
%
%  DESCANSO_DIAS = 10          # preparacion entre cultivos
%  PESOS = dict(aptitud=0.40, ocupacion=0.25, leguminosa=0.15, nitrogeno=0.10, diversidad=0.10)
%  PENAL_SOLANACEA_REPETIDA = 0.20
%  PENAL_FAMILIA_REPETIDA = 0.05
%
%
%  def _fecha(x):
%      return pd.Timestamp(x)
%
%
%  def _planear(secuencia, ventanas, inicio):
%      """Programa la secuencia: siembra lo antes posible dentro de cada ventana. Devuelve lista o None."""
%      t, plan = _fecha(inicio), []
%      for esp in secuencia:
%          mejor = None
%          for w in ventanas[esp]:
%              d0, d1 = _fecha(w["siembra_desde"]), _fecha(w["siembra_hasta"])
%              siembra = max(t, d0)
%              if siembra > d1:
%                  continue
%              frac = 0 if d1 == d0 else (siembra - d0).days / max((d1 - d0).days, 1)
%              dias = round(w["dias_a_cosecha_desde"] + frac * (w["dias_a_cosecha_hasta"] - w["dias_a_cosecha_desde"]))
%              cand = (siembra, dias, w)
%              if mejor is None or siembra < mejor[0]:
%                  mejor = cand
%          if mejor is None:
%              return None
%          siembra, dias, w = mejor
%          cosecha = siembra + pd.Timedelta(days=int(dias))
%          plan.append({"especie": esp, "siembra": siembra, "cosecha": cosecha, "dias": int(dias),
%                       "aptitud": w.get("aptitud_media_tramo") or 0.0})
%          t = cosecha + pd.Timedelta(days=DESCANSO_DIAS)
%      return plan
%
%
%  def mejores_rotaciones(fichas_sector, cultivos, inicio, dias_horizonte=365, max_ciclos=4, top=3):
%      """fichas_sector: fichas (DataFrame) de UNA celda. Devuelve lista de rotaciones ordenadas por puntaje."""
%      if fichas_sector is None or len(fichas_sector) == 0:
%          return []
%      info = cultivos.set_index("especie")
%      ventanas = {e: g.to_dict("records") for e, g in fichas_sector.groupby("especie")}
%      especies = sorted(ventanas)
%      inicio = _fecha(inicio)
%      fin = inicio + pd.Timedelta(days=dias_horizonte)
%      out, vistos = [], set()
%      for k in range(2, max_ciclos + 1):
%          for seq in itertools.product(especies, repeat=k):
%              if any(a == b or info.loc[a, "familia"] == info.loc[b, "familia"] for a, b in zip(seq, seq[1:])):
%                  continue
%              plan = _planear(seq, ventanas, inicio)
%              if plan is None or plan[-1]["cosecha"] > fin:
%                  continue
%              fams = [info.loc[p["especie"], "familia"] for p in plan]
%              leg = [str(info.loc[p["especie"], "fija_nitrogeno"]).lower() == "si" for p in plan]
%              dias_cultivo = sum(p["dias"] for p in plan)
%              ocupacion = min(dias_cultivo / dias_horizonte, 1.0)
%              apt = sum(p["aptitud"] for p in plan) / len(plan)
%              tiene_leg = any(leg)
%              # nitrogeno: leguminosa seguida de cultivo exigente (cereal o solanacea)
%              n_credito = any(leg[i] and fams[i + 1] in ("Poaceae", "Solanaceae") for i in range(len(plan) - 1))
%              diversidad = len(set(fams)) / len(plan)
%              pen = PENAL_SOLANACEA_REPETIDA * max(fams.count("Solanaceae") - 1, 0)
%              pen += PENAL_FAMILIA_REPETIDA * (len(fams) - len(set(fams)))
%              puntaje = (PESOS["aptitud"] * apt + PESOS["ocupacion"] * ocupacion
%                         + PESOS["leguminosa"] * tiene_leg + PESOS["nitrogeno"] * n_credito
%                         + PESOS["diversidad"] * diversidad - pen)
%              clave = (tuple(p["especie"] for p in plan))
%              if clave in vistos:
%                  continue
%              vistos.add(clave)
%              motivos = [f"Aptitud media {apt:.2f}", f"Usa {dias_cultivo} de {dias_horizonte} dias ({ocupacion:.0%})"]
%              motivos.append("Incluye leguminosa (fija nitrogeno)" if tiene_leg else "No incluye leguminosa")
%              if n_credito:
%                  motivos.append("Leguminosa antes de un cultivo exigente en nitrogeno")
%              motivos.append(f"{len(set(fams))} familia(s) botanica(s) distintas")
%              if pen:
%                  motivos.append(f"Penalizacion {pen:.2f} por repetir familia")
%              out.append({"secuencia": plan, "puntaje": round(puntaje, 3), "motivos": motivos,
%                          "ciclos": len(plan), "fin": plan[-1]["cosecha"]})
%      out.sort(key=lambda r: (-r["puntaje"], r["fin"]))
%      return out[:top]
%
%
%  def prompt_ia(sector, rotaciones, cultivos_cuidados, suelo="sin dato", prioridades="salud del suelo y ahorro de agua"):
%      resumen = [{"puntaje": r["puntaje"], "motivos": r["motivos"],
%                  "secuencia": [{**p, "siembra": str(p["siembra"].date()), "cosecha": str(p["cosecha"].date())} for p in r["secuencia"]]}
%                 for r in rotaciones]
%      return ("Eres un agronomo asesor. Para el sector " + str(sector) + " (suelo: " + suelo + "; prioridades: " + prioridades +
%              ") un optimizador por reglas propuso estas rotaciones (clima: promedio historico NASA POWER):\n" +
%              json.dumps(resumen, ensure_ascii=False) + "\nCuidados generales por cultivo:\n" +
%              json.dumps(cultivos_cuidados, ensure_ascii=False) +
%              "\nExplica en lenguaje sencillo cual elegirias y por que, y cuidados por cultivo y epoca. Senala incertidumbres y que no es pronostico.")
%
%
%  def explicar_con_ia(prompt, modelo="claude-sonnet-5-5"):
%      if not os.environ.get("ANTHROPIC_API_KEY"):
%          return None
%      import anthropic
%      r = anthropic.Anthropic().messages.create(model=modelo, max_tokens=1500, messages=[{"role": "user", "content": prompt}])
%      return r.content[0].text

%% ===== FILE: src/run.py =====
%  """Uso:
%    python -m src.run --sintetico
%    python -m src.run --clima data/power_diario.csv --celdas data/celdas.csv
%  Genera dos conjuntos de resultados en salidas/:
%    reciente/       -> ultimos meses OBSERVADOS (que paso)
%    planificacion/  -> proximos 12 meses con clima PROMEDIO historico por dia (que se podria sembrar)
%  celdas.csv: celda_id,lat,lon,elev,dist_rio_m,nodo_lat,nodo_lon"""
%  import argparse
%  import copy
%  import json
%  import os
%  import pandas as pd
%  import yaml
%  from .suitability import evaluar
%  from . import sintetico
%
%  CRIT = ["T2M", "T2M_MAX", "T2M_MIN", "PRECTOTCORR", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN"]
%
%
%  def cargar_clima(ruta):
%      d = pd.read_csv(ruta, parse_dates=["fecha"]).drop_duplicates(["lat", "lon", "fecha"], keep="last")
%      out = {}
%      for (la, lo), g in d.groupby(["lat", "lon"]):
%          g = g.sort_values("fecha").reset_index(drop=True)
%          ok = g[CRIT].notna().all(axis=1)
%          if ok.any():                       # recorta el final si POWER aun no publica alguna variable
%              g = g.loc[: ok[ok].index.max()]
%          out[(la, lo)] = g.interpolate(limit=3)
%      return out
%
%
%  def guardar(salida, modo, quinc, fichas, cfg):
%      d = os.path.join(salida, modo)
%      os.makedirs(d, exist_ok=True)
%      tols = list(fichas)
%      base = cfg["regla_permanencia"]["tolerancia"]
%      f0 = fichas[min(tols, key=lambda t: abs(t - base))]
%      quinc["aptitud"] = quinc["aptitud"].round(3)
%      quinc.to_csv(os.path.join(d, "aptitud_quincenal.csv.gz"), index=False)
%      f0.to_json(os.path.join(d, "fichas.json"), orient="records", force_ascii=False)
%      resumen = {str(t): {"fichas": len(f), "celdas_con_ficha": int(f["celda"].nunique()) if len(f) else 0,
%                          "por_especie": f["especie"].value_counts().to_dict() if len(f) else {}} for t, f in fichas.items()}
%      json.dump(resumen, open(os.path.join(d, "sensibilidad.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
%      print(f"[{modo}]")
%      for t, v in resumen.items():
%          print("  tolerancia", t, "->", v["fichas"], "fichas en", v["celdas_con_ficha"], "celdas")
%
%
%  def main():
%      ap = argparse.ArgumentParser()
%      ap.add_argument("--config", default="config.yaml")
%      ap.add_argument("--sintetico", action="store_true")
%      ap.add_argument("--clima")
%      ap.add_argument("--celdas")
%      ap.add_argument("--cultivos", default="data/cultivos_base.csv")
%      ap.add_argument("--salida", default="salidas")
%      a = ap.parse_args()
%      cfg = yaml.safe_load(open(a.config, encoding="utf-8"))
%      cultivos = pd.read_csv(a.cultivos)
%      if a.sintetico:
%          clima = {0: sintetico.clima_sintetico(anios=3)}
%          celdas = pd.DataFrame({"celda_id": ["alta", "media", "baja"], "lat": 2.4, "lon": -76.6,
%                                 "elev": [2900, 2200, 1700], "dist_rio_m": [2000, 300, 100], "nodo_id": 0})
%      else:
%          clima = cargar_clima(a.clima)
%          celdas = pd.read_csv(a.celdas)
%          celdas["nodo_id"] = list(zip(celdas["nodo_lat"], celdas["nodo_lon"]))
%      tols = cfg["regla_permanencia"]["sensibilidad"]
%      for modo in ("reciente", "climatologia"):
%          c2 = copy.deepcopy(cfg)
%          c2["linea_tiempo"]["modo"] = modo
%          quinc, fichas = evaluar(clima, celdas, cultivos, c2, tolerancias=tols)
%          guardar(a.salida, "reciente" if modo == "reciente" else "planificacion", quinc, fichas, c2)
%
%
%  if __name__ == "__main__":
%      main()

%% ===== FILE: src/actualizar.py =====
%  """Descarga/actualiza NASA POWER de forma incremental.
%    python -m src.actualizar            # crea o actualiza data/power_diario.csv
%  POWER publica meteorologia con ~2-3 dias de retraso y radiacion con ~5-7; ademas los ultimos dias
%  se revisan despues, por eso cada actualizacion vuelve a bajar los ultimos 60 dias (solape)."""
%  import argparse
%  import os
%  from datetime import datetime, timezone
%  import pandas as pd
%  import yaml
%  from .power_client import descargar_nodo, nodos_region
%
%
%  def actualizar(cfg, ruta, solape_dias=60):
%      p = cfg["power"]
%      hoy = datetime.now(timezone.utc).strftime("%Y%m%d")
%      viejo = None
%      inicio = str(p["inicio"])
%      if os.path.exists(ruta):
%          viejo = pd.read_csv(ruta, parse_dates=["fecha"])
%          inicio = (viejo["fecha"].max() - pd.Timedelta(days=solape_dias)).strftime("%Y%m%d")
%      nuevos = []
%      for lat, lon in nodos_region(cfg):
%          print("nodo", lat, lon, "desde", inicio, "hasta", hoy)
%          nuevos.append(descargar_nodo(lat, lon, p["parametros"], inicio, hoy, p["comunidad"]))
%      nuevo = pd.concat(nuevos)
%      if viejo is not None:
%          corte = pd.to_datetime(inicio, format="%Y%m%d")
%          nuevo = pd.concat([viejo[viejo["fecha"] < corte], nuevo])
%      nuevo = nuevo.drop_duplicates(["lat", "lon", "fecha"], keep="last").sort_values(["lat", "lon", "fecha"])
%      nuevo.to_csv(ruta, index=False)
%      print("guardado", ruta, len(nuevo), "filas; ultimo dia:", nuevo["fecha"].max().date())
%
%
%  if __name__ == "__main__":
%      ap = argparse.ArgumentParser()
%      ap.add_argument("--config", default="config.yaml")
%      ap.add_argument("--salida", default="data/power_diario.csv")
%      a = ap.parse_args()
%      actualizar(yaml.safe_load(open(a.config, encoding="utf-8")), a.salida)

%% ===== FILE: src/sintetico.py =====
%  """Datos sintéticos SOLO para probar el flujo sin internet. No usar en resultados reales."""
%  import numpy as np
%  import pandas as pd
%
%
%  def clima_sintetico(lat=2.4, lon=-76.6, elev_power=2200, anios=3, semilla=0):
%      rng = np.random.default_rng(semilla)
%      f = pd.date_range("2020-01-01", periods=365 * anios, freq="D")
%      doy = f.dayofyear.values
%      tm = 14 + 1.0 * np.sin(2 * np.pi * (doy - 60) / 365) + rng.normal(0, 0.8, len(f))
%      lluvia_s = 0.5 + 0.5 * np.cos(2 * np.pi * (doy - 300) / 182)   # dos épocas lluviosas
%      p = rng.gamma(0.6, 8 * lluvia_s + 0.5)
%      return pd.DataFrame({"fecha": f, "T2M": tm, "T2M_MAX": tm + 5, "T2M_MIN": tm - 5,
%                           "PRECTOTCORR": p, "RH2M": 80 + rng.normal(0, 4, len(f)),
%                           "WS2M": 2 + rng.random(len(f)), "ALLSKY_SFC_SW_DWN": 16 + rng.normal(0, 3, len(f)),
%                           "lat": lat, "lon": lon, "elev_power": elev_power})

%% ===== FILE: app.py =====
%  """App Streamlit: aptitud de cultivos por sector (NASA POWER) + rotaciones recomendadas.
%  Ejecutar:  streamlit run app.py"""
%  import json
%  import os
%  import numpy as np
%  import pandas as pd
%  import pydeck as pdk
%  import streamlit as st
%  from src.rotacion import mejores_rotaciones, prompt_ia, explicar_con_ia
%
%  BASE = os.path.dirname(os.path.abspath(__file__))
%  UMBRAL = 0.6
%  st.set_page_config(page_title="Rotación de cultivos con datos NASA", layout="wide")
%
%
%  @st.cache_data
%  def cargar(modo):
%      d = os.path.join(BASE, "salidas", modo)
%      apt = pd.read_csv(os.path.join(d, "aptitud_quincenal.csv.gz"), parse_dates=["quincena"])
%      fichas = pd.read_json(os.path.join(d, "fichas.json"), dtype={"celda": str})
%      return apt, fichas
%
%
%  @st.cache_data
%  def cargar_base():
%      celdas = pd.read_csv(os.path.join(BASE, "data", "celdas.csv"))
%      cultivos = pd.read_csv(os.path.join(BASE, "data", "cultivos_base.csv"))
%      cuid = pd.read_csv(os.path.join(BASE, "data", "cuidados_cultivos.csv")).set_index("especie")
%      return celdas, cultivos, cuid
%
%
%  celdas, cultivos, cuidados = cargar_base()
%
%  TX = {
%   "en": dict(
%    title="Crop rotation with NASA data (NASA POWER)",
%    caption="Area: Alto Cauca – Macizo Colombiano (Colombia) · 1 km cells · maize, bean and pea temperatures verified with FAO; potato and cycle parameters are preliminary",
%    opts="Options", period="Period", p_plan="Planning (next 12 months, average climate)", p_obs="Observed (last 12 months)",
%    species="Crop (for the map)", read="**How to read the color:** green = suitable (score ≥ 0.6); red = not suitable.",
%    notfc="Planning **is not a forecast**: it uses the historical average of each day of the year.",
%    tabs=["Map and timeline", "Recommended rotation by sector", "How it works"],
%    fort="Fortnight", cells_ok="Suitable cells", mean_apt="Mean suitability", mean_alt="Mean altitude of suitable cells (m)",
%    tip="Cell {celda}\nSuitability: {aptitud_txt}\nAltitude: {elev} m\nDistance to river: {dist_rio_m} m",
%    mapcap="Each dot is a 1 km cell. Altitude comes from Copernicus DEM; climate from NASA POWER corrected for altitude.",
%    pick="Choose a sector", how="How to choose", how_opts=["Example by altitude", "Coordinates"], alt="Approximate altitude (m)",
%    lat="Latitude", lon="Longitude", sector="Sector", river="river at", altl="altitude",
%    nofc="In this sector no crop of the catalogue completes its cycle with the average climate. Try another altitude or coordinate.",
%    viable="Viable crops in this sector (next 12 months)",
%    cols={"especie":"crop","siembra_desde":"sowing from","siembra_hasta":"sowing until","dias_a_cosecha_desde":"days to harvest",
%          "cosecha_desde":"harvest from","cosecha_hasta":"harvest until","aptitud_media_tramo":"mean suitability"},
%    rots="Recommended rotations", norot="With the viable crops of this sector no rotation of at least 2 crops from different families fits in 12 months. You can plant a single crop from the table above.",
%    option="Option", score="score", rcols=["order","crop","sowing","harvest","days","suitability"], why="**Why:**", care="Care", harvest="Harvest",
%    note="Care tips are guidance (PRELIMINARY) and must be validated by an agronomist. Dates use average climate, not a forecast.",
%    ai_btn="Explain with AI (optional)", ai_info="To enable the AI explanation set the ANTHROPIC_API_KEY environment variable. The rotations above work without AI.",
%    chart="Suitability by fortnight in this sector (first 6 months)",
%   ),
%   "es": dict(
%    title="Rotación de cultivos con datos NASA (NASA POWER)",
%    caption="Zona: Alto Cauca – Macizo Colombiano · celdas de 1 km · temperaturas de maíz, frijol y arveja verificadas con FAO; papa y ciclos son preliminares",
%    opts="Opciones", period="Periodo", p_plan="Planificación (próximos 12 meses, clima promedio)", p_obs="Observado (últimos 12 meses)",
%    species="Especie (para el mapa)", read="**Cómo leer el color:** verde = apto (puntaje ≥ 0,6); rojo = no apto.",
%    notfc="Planificación **no es un pronóstico**: usa el promedio histórico de cada día del año.",
%    tabs=["Mapa y línea de tiempo", "Rotación recomendada por sector", "Cómo funciona"],
%    fort="Quincena", cells_ok="Celdas aptas", mean_apt="Aptitud media", mean_alt="Altitud media de celdas aptas (m)",
%    tip="Celda {celda}\nAptitud: {aptitud_txt}\nAltitud: {elev} m\nDistancia a río: {dist_rio_m} m",
%    mapcap="Cada punto es una celda de 1 km. La altitud viene de Copernicus DEM; el clima, de NASA POWER corregido por altitud.",
%    pick="Elige un sector", how="Cómo elegir", how_opts=["Ejemplo por altitud", "Coordenadas"], alt="Altitud aproximada (m)",
%    lat="Latitud", lon="Longitud", sector="Sector", river="río a", altl="altitud",
%    nofc="En este sector ninguna especie del catálogo completa su ciclo con el clima promedio. Prueba otra altitud o coordenada.",
%    viable="Especies viables en este sector (próximos 12 meses)",
%    cols={"siembra_desde":"siembra desde","siembra_hasta":"siembra hasta","dias_a_cosecha_desde":"días a cosecha",
%          "cosecha_desde":"cosecha desde","cosecha_hasta":"cosecha hasta","aptitud_media_tramo":"aptitud media"},
%    rots="Rotaciones recomendadas", norot="Con las especies viables de este sector no se logra una rotación de al menos 2 cultivos de familias distintas dentro de 12 meses. Puedes sembrar una sola especie de la tabla de arriba.",
%    option="Opción", score="puntaje", rcols=["orden","especie","siembra","cosecha","días","aptitud"], why="**Por qué:**", care="Cuidados", harvest="Cosecha",
%    note="Los cuidados son orientativos (PRELIMINAR) y deben validarse con un agrónomo. Las fechas usan clima promedio, no un pronóstico.",
%    ai_btn="Explicar con IA (opcional)", ai_info="Para activar la explicación con IA define la variable de entorno ANTHROPIC_API_KEY. Las rotaciones de arriba funcionan sin IA.",
%    chart="Aptitud por quincena en este sector (primeros 6 meses)",
%   ),
%  }
%  NOMBRE_EN = {"maiz": "maize", "frijol": "bean", "papa": "potato", "arveja": "pea"}
%  CUID_EN = {
%   "maiz": ("Cereal demanding in nitrogen; a good crop after a legume",
%            "Sow with enough soil moisture; split nitrogen fertilization; weed control in the first weeks; watch for fall armyworm.",
%            "Physiological maturity of the grain; dry cob for grain or milky stage for fresh corn."),
%   "frijol": ("Legume: fixes nitrogen and improves the soil for the next crop",
%              "Well-drained soil, no waterlogging; avoid excess nitrogen; watch for rust and anthracnose in wet periods; staking for climbing types.",
%              "When pods mature and dry; staggered picking for climbing types."),
%   "papa": ("Solanaceae demanding in nutrients; avoid repeating solanaceous crops back to back",
%            "Healthy or certified seed; hilling; watch for late blight (Phytophthora) in rainy weather; rotate with another family to break soil pests.",
%            "When the foliage dries and the tuber skin sets."),
%   "arveja": ("Cool-climate legume: fixes nitrogen",
%              "Well-drained soil; staking for climbing varieties; watch for ascochyta, mildew and anthracnose in wet periods.",
%              "Green (full pod) or dry depending on use."),
%  }
%
%
%  def motivo_en(m):
%      import re
%      r = [(r"Aptitud media ([\d.]+)", r"Mean suitability \1"),
%           (r"Usa (\d+) de (\d+) dias \((\d+%)\)", r"Uses \1 of \2 days (\3)"),
%           (r"Incluye leguminosa \(fija nitrogeno\)", "Includes a legume (fixes nitrogen)"),
%           (r"No incluye leguminosa", "No legume included"),
%           (r"Leguminosa antes de un cultivo exigente en nitrogeno", "Legume before a nitrogen-demanding crop"),
%           (r"(\d+) familia\(s\) botanica\(s\) distintas", r"\1 different botanical family(ies)"),
%           (r"Penalizacion ([\d.]+) por repetir familia", r"Penalty \1 for repeating a family")]
%      for p, q in r:
%          m = re.sub(p, q, m)
%      return m
%
%
%  with st.sidebar:
%      idioma = st.radio("Language / Idioma", ["English", "Español"])
%  L = "en" if idioma == "English" else "es"
%  t = TX[L]
%
%
%  def nm(e):
%      return NOMBRE_EN.get(e, e) if L == "en" else e
%
%
%  st.title(t["title"])
%  st.caption(t["caption"])
%
%  with st.sidebar:
%      st.header(t["opts"])
%      periodo = st.radio(t["period"], [t["p_plan"], t["p_obs"]])
%      modo = "planificacion" if periodo == t["p_plan"] else "reciente"
%      esp = st.selectbox(t["species"], sorted(cultivos["especie"]), format_func=nm)
%      st.markdown(t["read"])
%      st.markdown(t["notfc"])
%
%  apt, fichas = cargar(modo)
%  apt_plan, fichas_plan = cargar("planificacion")
%  tab1, tab2, tab3 = st.tabs(t["tabs"])
%
%  # ---------------- Map ----------------
%  with tab1:
%      quincenas = sorted(apt["quincena"].unique())
%      q = st.select_slider(t["fort"], options=quincenas, format_func=lambda d: pd.Timestamp(d).strftime("%Y-%m-%d"))
%      d = apt[(apt["especie"] == esp) & (apt["quincena"] == q)].merge(celdas, left_on="celda", right_on="celda_id")
%      d["apta"] = d["aptitud"] >= UMBRAL
%      d["color"] = d["aptitud"].apply(lambda v: [int(220 * (1 - v)), int(190 * v), 60, 170])
%      d["aptitud_txt"] = d["aptitud"].round(2).astype(str)
%      c1, c2, c3 = st.columns(3)
%      c1.metric(t["cells_ok"], f"{d['apta'].mean():.0%}")
%      c2.metric(t["mean_apt"], f"{d['aptitud'].mean():.2f}")
%      c3.metric(t["mean_alt"], f"{d.loc[d['apta'], 'elev'].mean():.0f}" if d["apta"].any() else "–")
%      st.pydeck_chart(pdk.Deck(
%          layers=[pdk.Layer("ScatterplotLayer", d, get_position="[lon, lat]", get_fill_color="color", get_radius=520, pickable=True)],
%          initial_view_state=pdk.ViewState(latitude=float(celdas["lat"].mean()), longitude=float(celdas["lon"].mean()), zoom=8.3),
%          tooltip={"text": t["tip"]}))
%      st.caption(t["mapcap"])
%
%  # ---------------- Rotation ----------------
%  with tab2:
%      st.subheader(t["pick"])
%      metodo = st.radio(t["how"], t["how_opts"], horizontal=True)
%      con_ficha = set(fichas_plan["celda"].unique())
%      cel = celdas[celdas["celda_id"].isin(con_ficha)]
%      if metodo == t["how_opts"][0]:
%          alt = st.select_slider(t["alt"], options=[900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300], value=1800)
%          sector = cel.iloc[(cel["elev"] - alt).abs().argsort().iloc[0]]
%      else:
%          a, b = st.columns(2)
%          lat = a.number_input(t["lat"], 2.0, 2.8, 2.40, 0.01)
%          lon = b.number_input(t["lon"], -76.9, -76.2, -76.55, 0.01)
%          sector = celdas.iloc[(((celdas["lat"] - lat) ** 2 + (celdas["lon"] - lon) ** 2)).argsort().iloc[0]]
%      sid = sector["celda_id"]
%      st.info(f"{t['sector']} **{sid}** · lat {sector['lat']:.3f}, lon {sector['lon']:.3f} · {t['altl']} {sector['elev']:.0f} m · "
%              f"{t['river']} {sector['dist_rio_m']:.0f} m")
%      fs = fichas_plan[fichas_plan["celda"] == sid]
%      if len(fs) == 0:
%          st.warning(t["nofc"])
%      else:
%          inicio = pd.Timestamp(apt_plan["quincena"].min())
%          rots = mejores_rotaciones(fs, cultivos, inicio, dias_horizonte=365, max_ciclos=4, top=3)
%          st.subheader(t["viable"])
%          tabla = fs[["especie", "siembra_desde", "siembra_hasta", "dias_a_cosecha_desde", "cosecha_desde", "cosecha_hasta", "aptitud_media_tramo"]].copy()
%          tabla["especie"] = tabla["especie"].map(nm)
%          tabla = tabla.rename(columns=t["cols"])
%          st.dataframe(tabla, hide_index=True, use_container_width=True)
%          st.subheader(t["rots"])
%          if not rots:
%              st.warning(t["norot"])
%          for i, r in enumerate(rots, 1):
%              with st.expander(f"{t['option']} {i}: " + " → ".join(nm(p["especie"]) for p in r["secuencia"]) + f"   ({t['score']} {r['puntaje']:.2f})", expanded=(i == 1)):
%                  st.dataframe(pd.DataFrame([dict(zip(t["rcols"], [n, nm(p["especie"]), p["siembra"].date(), p["cosecha"].date(),
%                                                                    p["dias"], round(p["aptitud"], 2)])) for n, p in enumerate(r["secuencia"], 1)]),
%                               hide_index=True, use_container_width=True)
%                  mot = [motivo_en(m) for m in r["motivos"]] if L == "en" else r["motivos"]
%                  st.markdown(t["why"] + " " + " · ".join(mot))
%                  for p in r["secuencia"]:
%                      e = p["especie"]
%                      if L == "en" and e in CUID_EN:
%                          rol, cu, co = CUID_EN[e]
%                          st.markdown(f"- **{nm(e)}** ({rol}). {t['care']}: {cu} {t['harvest']}: {co}")
%                      elif e in cuidados.index:
%                          c = cuidados.loc[e]
%                          st.markdown(f"- **{e}** ({c['rol_en_rotacion']}). {t['care']}: {c['cuidados_clave']} {t['harvest']}: {c['cosecha']}")
%          if rots:
%              st.caption(t["note"])
%              if st.button(t["ai_btn"]):
%                  p = prompt_ia(sid, rots, cuidados.reset_index().to_dict("records"))
%                  if L == "en":
%                      p += "\nAnswer in English."
%                  txt = explicar_con_ia(p)
%                  if txt:
%                      st.markdown(txt)
%                  else:
%                      st.info(t["ai_info"])
%          ap_s = apt_plan[apt_plan["celda"] == sid].pivot(index="quincena", columns="especie", values="aptitud")
%          ap_s.columns = [nm(c) for c in ap_s.columns]
%          st.subheader(t["chart"])
%          st.line_chart(ap_s)
%
%  # ---------------- How it works ----------------
%  with tab3:
%      if L == "en":
%          st.markdown("""
%  ### What this tool does
%  It shows in which sectors of the area each crop can be planted and proposes rotations that protect the soil, based on **NASA observations**.
%
%  ### Where the data comes from
%  - **Climate:** NASA POWER (MERRA-2 reanalysis): daily temperature, rain, humidity, wind and radiation since 1981. Cells of ~50 km. https://power.larc.nasa.gov/
%  - **Altitude:** Copernicus DEM GLO-30 (30 m). Used to correct temperature with height (−0.0065 °C per metre).
%  - **Rivers:** HydroRIVERS (HydroSHEDS). The distance from each cell to the nearest river is used.
%  - **Crops:** catalogue with temperature ranges, growing-degree-day cycle and Kc (FAO-56). Temperatures of **maize** (FAO Ecocrop), **bean** and **pea** (FAO Land & Water) are verified; potato, base temperatures, degree-days and cycle lengths are own estimates (**preliminary**).
%
%  ### Calculation steps
%  1. For each day and cell the **evapotranspiration** (FAO-56 Penman–Monteith) and the water each crop needs are computed.
%  2. **Suitability score (0–1)** = the lower of the temperature score and the water score (law of the minimum, as in Ecocrop).
%  3. A day is **suitable** if the score ≥ 0.6.
%  4. **Permanence rule:** a crop gets a *record* in a sector if there is a continuous run of suitable days accumulating at least 95 % of the growing-degree-days of its cycle (±5 % tolerance).
%  5. **Rotations:** the crops with a record in the sector are combined into sequences of 2 to 4 crops, never repeating a family back to back, and scored by suitability, use of the year, legume, nitrogen and diversity.
%
%  ### Limitations (important)
%  - NASA POWER has low resolution and rain is its most uncertain variable; it still needs calibration with IDEAM stations.
%  - Soil is not yet part of the score.
%  - FAO values are global and do not reflect Andean practice: high-altitude sectors lose coverage.
%  - The 0.6 threshold and the rotation weights are design criteria that must be validated.
%  - *Planning* mode is not a weather forecast.
%  """)
%      else:
%          st.markdown("""
%  ### Qué hace esta herramienta
%  Indica en qué sectores de la zona puede sembrarse cada especie y propone rotaciones que cuidan el suelo, a partir de **observaciones de la NASA**.
%
%  ### De dónde salen los datos
%  - **Clima:** NASA POWER (reanálisis MERRA-2): temperatura, lluvia, humedad, viento y radiación diarios desde 1981. Celdas de ~50 km. https://power.larc.nasa.gov/
%  - **Altitud:** Copernicus DEM GLO-30 (30 m). Sirve para corregir la temperatura por altura (−0,0065 °C por metro).
%  - **Ríos:** HydroRIVERS (HydroSHEDS). Se usa la distancia de cada celda al río más cercano.
%  - **Cultivos:** catálogo con rangos de temperatura, ciclo en grados-día y coeficiente Kc (FAO-56). Las temperaturas de **maíz** (FAO Ecocrop), **frijol** y **arveja** (FAO Land & Water) están verificadas; papa, temperaturas base, grados-día y duración del ciclo son estimaciones propias (**preliminares**).
%
%  ### Pasos del cálculo
%  1. Cada día y celda se calcula la **evapotranspiración** (FAO-56 Penman–Monteith) y el agua que necesita cada cultivo.
%  2. **Puntaje de aptitud (0–1)** = el menor entre el puntaje de temperatura y el de agua (ley del mínimo, como en Ecocrop).
%  3. Un día es **apto** si el puntaje ≥ 0,6.
%  4. **Regla de permanencia:** una especie recibe *ficha* en un sector si hay un tramo continuo de días aptos que acumula al menos el 95 % de los grados-día de su ciclo (tolerancia ±5 %).
%  5. **Rotaciones:** se combinan las especies con ficha del sector en secuencias de 2 a 4 cultivos, sin repetir familia seguida, y se puntúan por aptitud, uso del año, leguminosa, nitrógeno y diversidad.
%
%  ### Limitaciones (importantes)
%  - NASA POWER tiene baja resolución y la lluvia es su variable más incierta; falta calibrar con estaciones del IDEAM.
%  - El suelo todavía no entra en el puntaje.
%  - Los valores FAO son globales y no reflejan la práctica andina: los sectores altos pierden cobertura.
%  - El umbral de 0,6 y los pesos de la rotación son criterios de diseño que deben validarse.
%  - El modo *Planificación* no es un pronóstico del clima.
%  """)

%% ===== FILE: data/cultivos_base.csv =====
%  especie,familia,t_min,t_opt_min,t_opt_max,t_max,t_base_gdd,gdd_ciclo,ciclo_dias,kc_medio,fija_nitrogeno,fuente,estado
%  maiz,Poaceae,10,18,33,47,10,1500,150,1.20,no,"Temperaturas: FAO Ecocrop (ficha Zea mays, id 2175); Kc: FAO-56; Tbase/GDD/ciclo: propios (ciclo dentro del rango Ecocrop 65-365 d)",TEMPERATURAS VERIFICADAS
%  frijol,Fabaceae,10,15,20,27,10,900,110,1.15,si,"Temperaturas y ciclo 110 d: FAO Land & Water (Bean); Kc: FAO-56; GDD: propio",TEMPERATURAS VERIFICADAS
%  papa,Solanaceae,3,12,20,28,7,1300,140,1.15,no,"Ciclo 140 d dentro del rango FAO (120-150 d medio); Kc: FAO-56; temperaturas propias (FAO da umbrales de tuberizacion, no equivalentes)",PRELIMINAR
%  arveja,Fabaceae,10,17,17,23,4,1300,110,1.15,si,"Temperaturas: FAO Land & Water (Pea): min 10, optimo 17, max 23; ciclo 110 d dentro del rango FAO; Kc: FAO-56; GDD: propio",TEMPERATURAS VERIFICADAS
