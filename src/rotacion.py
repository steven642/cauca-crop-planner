"""Rotaciones recomendadas por sector.
1) mejores_rotaciones(): optimizador por reglas (siempre funciona, sin internet ni clave).
2) explicar_con_ia(): opcional, redacta/explica con un modelo si hay ANTHROPIC_API_KEY.
Las reglas y pesos son criterio de diseno (inspirado en principios de rotacion: alternar familias,
incluir leguminosas, no repetir solanaceas) y deben validarse con un agronomo."""
import itertools
import json
import os
import pandas as pd

DESCANSO_DIAS = 10          # preparacion entre cultivos
PESOS = dict(aptitud=0.40, ocupacion=0.25, leguminosa=0.15, nitrogeno=0.10, diversidad=0.10)
PENAL_SOLANACEA_REPETIDA = 0.20
PENAL_FAMILIA_REPETIDA = 0.05


def _fecha(x):
    return pd.Timestamp(x)


def _planear(secuencia, ventanas, inicio):
    """Programa la secuencia: siembra lo antes posible dentro de cada ventana. Devuelve lista o None."""
    t, plan = _fecha(inicio), []
    for esp in secuencia:
        mejor = None
        for w in ventanas[esp]:
            d0, d1 = _fecha(w["siembra_desde"]), _fecha(w["siembra_hasta"])
            siembra = max(t, d0)
            if siembra > d1:
                continue
            frac = 0 if d1 == d0 else (siembra - d0).days / max((d1 - d0).days, 1)
            dias = round(w["dias_a_cosecha_desde"] + frac * (w["dias_a_cosecha_hasta"] - w["dias_a_cosecha_desde"]))
            cand = (siembra, dias, w)
            if mejor is None or siembra < mejor[0]:
                mejor = cand
        if mejor is None:
            return None
        siembra, dias, w = mejor
        cosecha = siembra + pd.Timedelta(days=int(dias))
        plan.append({"especie": esp, "siembra": siembra, "cosecha": cosecha, "dias": int(dias),
                     "aptitud": w.get("aptitud_media_tramo") or 0.0})
        t = cosecha + pd.Timedelta(days=DESCANSO_DIAS)
    return plan


def mejores_rotaciones(fichas_sector, cultivos, inicio, dias_horizonte=365, max_ciclos=4, top=3):
    """fichas_sector: fichas (DataFrame) de UNA celda. Devuelve lista de rotaciones ordenadas por puntaje."""
    if fichas_sector is None or len(fichas_sector) == 0:
        return []
    info = cultivos.set_index("especie")
    ventanas = {e: g.to_dict("records") for e, g in fichas_sector.groupby("especie")}
    especies = sorted(ventanas)
    inicio = _fecha(inicio)
    fin = inicio + pd.Timedelta(days=dias_horizonte)
    out, vistos = [], set()
    for k in range(2, max_ciclos + 1):
        for seq in itertools.product(especies, repeat=k):
            if any(a == b or info.loc[a, "familia"] == info.loc[b, "familia"] for a, b in zip(seq, seq[1:])):
                continue
            plan = _planear(seq, ventanas, inicio)
            if plan is None or plan[-1]["cosecha"] > fin:
                continue
            fams = [info.loc[p["especie"], "familia"] for p in plan]
            leg = [str(info.loc[p["especie"], "fija_nitrogeno"]).lower() == "si" for p in plan]
            dias_cultivo = sum(p["dias"] for p in plan)
            ocupacion = min(dias_cultivo / dias_horizonte, 1.0)
            apt = sum(p["aptitud"] for p in plan) / len(plan)
            tiene_leg = any(leg)
            # nitrogeno: leguminosa seguida de cultivo exigente (cereal o solanacea)
            n_credito = any(leg[i] and fams[i + 1] in ("Poaceae", "Solanaceae") for i in range(len(plan) - 1))
            diversidad = len(set(fams)) / len(plan)
            pen = PENAL_SOLANACEA_REPETIDA * max(fams.count("Solanaceae") - 1, 0)
            pen += PENAL_FAMILIA_REPETIDA * (len(fams) - len(set(fams)))
            puntaje = (PESOS["aptitud"] * apt + PESOS["ocupacion"] * ocupacion
                       + PESOS["leguminosa"] * tiene_leg + PESOS["nitrogeno"] * n_credito
                       + PESOS["diversidad"] * diversidad - pen)
            clave = (tuple(p["especie"] for p in plan))
            if clave in vistos:
                continue
            vistos.add(clave)
            motivos = [f"Aptitud media {apt:.2f}", f"Usa {dias_cultivo} de {dias_horizonte} dias ({ocupacion:.0%})"]
            motivos.append("Incluye leguminosa (fija nitrogeno)" if tiene_leg else "No incluye leguminosa")
            if n_credito:
                motivos.append("Leguminosa antes de un cultivo exigente en nitrogeno")
            motivos.append(f"{len(set(fams))} familia(s) botanica(s) distintas")
            if pen:
                motivos.append(f"Penalizacion {pen:.2f} por repetir familia")
            out.append({"secuencia": plan, "puntaje": round(puntaje, 3), "motivos": motivos,
                        "ciclos": len(plan), "fin": plan[-1]["cosecha"]})
    out.sort(key=lambda r: (-r["puntaje"], r["fin"]))
    return out[:top]


def prompt_ia(sector, rotaciones, cultivos_cuidados, suelo="sin dato", prioridades="salud del suelo y ahorro de agua"):
    resumen = [{"puntaje": r["puntaje"], "motivos": r["motivos"],
                "secuencia": [{**p, "siembra": str(p["siembra"].date()), "cosecha": str(p["cosecha"].date())} for p in r["secuencia"]]}
               for r in rotaciones]
    return ("Eres un agronomo asesor. Para el sector " + str(sector) + " (suelo: " + suelo + "; prioridades: " + prioridades +
            ") un optimizador por reglas propuso estas rotaciones (clima: promedio historico NASA POWER):\n" +
            json.dumps(resumen, ensure_ascii=False) + "\nCuidados generales por cultivo:\n" +
            json.dumps(cultivos_cuidados, ensure_ascii=False) +
            "\nExplica en lenguaje sencillo cual elegirias y por que, y cuidados por cultivo y epoca. Senala incertidumbres y que no es pronostico.")


def explicar_con_ia(prompt, modelo="claude-sonnet-5-5"):
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return None
    import anthropic
    r = anthropic.Anthropic().messages.create(model=modelo, max_tokens=1500, messages=[{"role": "user", "content": prompt}])
    return r.content[0].text
