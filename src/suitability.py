"""Aptitud diaria por celda y cultivo + regla de permanencia (tolerancia sobre grados-dia)
+ linea de tiempo quincenal sobre una ventana de N meses."""
import numpy as np
import pandas as pd
from .agro import eto_pm, gdd_diario, trapecio


def preparar_celda(clima, celda, cfg):
    """Corrige un nodo POWER a una celda (altitud, precip) y calcula ETo."""
    c = clima.copy()
    dz = celda["elev"] - c["elev_power"].iloc[0]
    g = cfg["correccion"]["gradiente_termico_c_por_m"]
    for v in ("T2M", "T2M_MAX", "T2M_MIN"):
        c[v] = c[v] + g * dz
    c["PRECTOTCORR"] = c["PRECTOTCORR"] * cfg["correccion"]["factor_precip"]
    doy = c["fecha"].dt.dayofyear.values
    c["ETO"] = eto_pm(c["T2M"].values, c["T2M_MAX"].values, c["T2M_MIN"].values,
                      c["RH2M"].values, c["WS2M"].values, c["ALLSKY_SFC_SW_DWN"].values,
                      celda["lat"], celda["elev"], doy)
    return c


def ventana_tiempo(c, cfg, meses=None):
    """Devuelve (serie_a_usar, inicio, fin) segun el modo de la linea de tiempo."""
    lt = cfg["linea_tiempo"]
    meses = meses or lt["meses"]
    w = cfg["aptitud"]["ventana_agua_dias"]
    ult = c["fecha"].max()
    if lt["modo"] == "climatologia":
        inicio = ult + pd.Timedelta(days=1)
        fin = inicio + pd.DateOffset(months=meses) - pd.Timedelta(days=1)
        fechas = pd.date_range(inicio, fin, freq="D")
        cols = ["T2M", "T2M_MAX", "T2M_MIN", "PRECTOTCORR", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN", "ETO"]
        clim = c.assign(doy=c["fecha"].dt.dayofyear.clip(upper=365)).groupby("doy")[cols].mean()
        fut = clim.reindex(np.minimum(fechas.dayofyear.values, 365)).reset_index(drop=True)
        fut.insert(0, "fecha", fechas)
        previo = c.tail(w)[["fecha"] + cols]
        return pd.concat([previo, fut], ignore_index=True), inicio, fin
    fin = ult if lt["fin"] == "auto" else pd.Timestamp(lt["fin"])
    inicio = fin - pd.DateOffset(months=meses) + pd.Timedelta(days=1)
    return c[c["fecha"] <= fin].reset_index(drop=True), inicio, fin


def apto_diario(c, cultivo, celda, cfg):
    a = cfg["aptitud"]
    w = a["ventana_agua_dias"]
    ts = trapecio(c["T2M"].values, cultivo["t_min"], cultivo["t_opt_min"], cultivo["t_opt_max"], cultivo["t_max"])
    etc = (c["ETO"] * cultivo["kc_medio"]).rolling(w, min_periods=w // 2).sum()
    oferta = c["PRECTOTCORR"].rolling(w, min_periods=w // 2).sum()
    if celda.get("dist_rio_m", 1e9) <= a["distancia_rio_riego_m"]:
        oferta = oferta + a["aporte_riego_mm_ventana"]
    ws = np.clip(oferta / etc.replace(0, np.nan), 0, 1).fillna(0).values
    score = np.minimum(ts, ws) if a.get("combinacion", "minimo") == "minimo" else ts * ws
    return score, score >= a["umbral_diario"]


def fichas_permanencia(c, apto, cultivo, tolerancia, score=None):
    """Tramos continuos aptos cuyo GDD acumulado >= gdd_ciclo*(1-tol).
    Devuelve ventana de siembra, dias estimados hasta cosecha y ventana de cosecha."""
    gdd = gdd_diario(c["T2M"].values, cultivo["t_base_gdd"])
    meta = cultivo["gdd_ciclo"] * (1 - tolerancia)
    fechas = c["fecha"].values
    res, n, i = [], len(apto), 0
    while i < n:
        if not apto[i]:
            i += 1
            continue
        j = i
        while j < n and apto[j]:
            j += 1
        tramo = gdd[i:j]
        acum_rev = np.cumsum(tramo[::-1])[::-1]   # GDD disponibles si siembra el dia k del tramo
        ok = np.where(acum_rev >= meta)[0]
        if len(ok):
            k0, k1 = int(ok[0]), int(ok[-1])

            def dur(k):                            # dias necesarios desde la siembra k hasta acumular la meta
                return int(np.searchsorted(np.cumsum(tramo[k:]), meta) + 1)
            d0, d1 = dur(k0), dur(k1)
            res.append({"siembra_desde": str(fechas[i + k0])[:10], "siembra_hasta": str(fechas[i + k1])[:10],
                        "dias_a_cosecha_desde": d0, "dias_a_cosecha_hasta": d1,
                        "cosecha_desde": str(fechas[i + k0 + d0 - 1])[:10],
                        "cosecha_hasta": str(fechas[i + k1 + d1 - 1])[:10],
                        "dias_tramo": int(j - i), "gdd_tramo": round(float(tramo.sum()), 1),
                        "aptitud_media_tramo": round(float(np.mean(score[i:j])), 3) if score is not None else None})
        i = j
    return res


def quincena_inicio(fechas):
    f = pd.Series(pd.to_datetime(fechas))
    return f.dt.to_period("M").dt.start_time + pd.to_timedelta((f.dt.day > 15) * 15, unit="D")


def recortar(clima, cfg):
    """Recorta la serie larga de un nodo a lo que realmente se usa (acelera con miles de celdas)."""
    lt, w = cfg["linea_tiempo"], cfg["aptitud"]["ventana_agua_dias"]
    ult = clima["fecha"].max()
    if lt["modo"] == "climatologia":
        return clima[clima["fecha"] >= ult - pd.DateOffset(years=20)].reset_index(drop=True)
    fin = ult if lt["fin"] == "auto" else pd.Timestamp(lt["fin"])
    ini = fin - pd.DateOffset(months=max(lt["meses"], lt.get("fichas_meses", lt["meses"]))) - pd.Timedelta(days=w + 5)
    return clima[clima["fecha"] >= ini].reset_index(drop=True)


def evaluar(clima_por_nodo, celdas, cultivos, cfg, tolerancias=None):
    """Devuelve (quincenal_df, {tolerancia: fichas_df}). Linea de tiempo = lt['meses']; fichas = lt['fichas_meses']."""
    tols = tolerancias or [cfg["regla_permanencia"]["tolerancia"]]
    lt = cfg["linea_tiempo"]
    m_vis, m_fic = lt["meses"], lt.get("fichas_meses", lt["meses"])
    clima_por_nodo = {k: recortar(v, cfg) for k, v in clima_por_nodo.items()}
    quinc, fichas = [], {t: [] for t in tols}
    for _, celda in celdas.iterrows():
        c0 = preparar_celda(clima_por_nodo[celda["nodo_id"]], celda, cfg)
        c, ini_f, fin_f = ventana_tiempo(c0, cfg, meses=m_fic)
        if lt["modo"] == "climatologia":
            ini_v, fin_v = ini_f, ini_f + pd.DateOffset(months=m_vis) - pd.Timedelta(days=1)
        else:
            fin_v, ini_v = fin_f, fin_f - pd.DateOffset(months=m_vis) + pd.Timedelta(days=1)
        mf = ((c["fecha"] >= ini_f) & (c["fecha"] <= fin_f)).values
        mv = ((c["fecha"] >= ini_v) & (c["fecha"] <= fin_v)).values
        cf = c[mf].reset_index(drop=True)
        qk = quincena_inicio(c[mv]["fecha"]).values
        for _, cult in cultivos.iterrows():
            score, apto = apto_diario(c, cult, celda, cfg)
            q = pd.Series(score[mv]).groupby(qk).mean()
            for f, v in q.items():
                quinc.append({"celda": celda["celda_id"], "especie": cult["especie"], "quincena": f, "aptitud": float(v)})
            for t in tols:
                for v in fichas_permanencia(cf, apto[mf], cult, t, score[mf]):
                    borde = pd.Timestamp(v["siembra_desde"]) <= ini_f + pd.Timedelta(days=2)
                    fichas[t].append({"celda": celda["celda_id"], "especie": cult["especie"],
                                      "familia": cult["familia"], "fija_nitrogeno": cult["fija_nitrogeno"],
                                      "ciclo_dias": int(cult["ciclo_dias"]), "tolerancia": t,
                                      "modo": lt["modo"], "ventana_meses": m_fic,
                                      "empieza_en_borde": bool(borde), **v})
    return pd.DataFrame(quinc), {t: pd.DataFrame(f) for t, f in fichas.items()}
