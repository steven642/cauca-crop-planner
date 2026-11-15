"""App Streamlit: aptitud de cultivos por sector (NASA POWER) + rotaciones recomendadas.
Ejecutar:  streamlit run app.py"""
import json
import os
import numpy as np
import pandas as pd
import pydeck as pdk
import streamlit as st
from src.rotacion import mejores_rotaciones, prompt_ia, explicar_con_ia

BASE = os.path.dirname(os.path.abspath(__file__))
UMBRAL = 0.6
st.set_page_config(page_title="Rotación de cultivos con datos NASA", layout="wide")


@st.cache_data
def cargar(modo):
    d = os.path.join(BASE, "salidas", modo)
    apt = pd.read_csv(os.path.join(d, "aptitud_quincenal.csv.gz"), parse_dates=["quincena"])
    fichas = pd.read_json(os.path.join(d, "fichas.json"), dtype={"celda": str})
    return apt, fichas


@st.cache_data
def cargar_base():
    celdas = pd.read_csv(os.path.join(BASE, "data", "celdas.csv"))
    cultivos = pd.read_csv(os.path.join(BASE, "data", "cultivos_base.csv"))
    cuid = pd.read_csv(os.path.join(BASE, "data", "cuidados_cultivos.csv")).set_index("especie")
    return celdas, cultivos, cuid


celdas, cultivos, cuidados = cargar_base()

TX = {
 "en": dict(
  title="Crop rotation with NASA data (NASA POWER)",
  caption="Area: Alto Cauca – Macizo Colombiano (Colombia) · 1 km cells · maize, bean and pea temperatures verified with FAO; potato and cycle parameters are preliminary",
  opts="Options", period="Period", p_plan="Planning (next 12 months, average climate)", p_obs="Observed (last 12 months)",
  species="Crop (for the map)", read="**How to read the color:** green = suitable (score ≥ 0.6); red = not suitable.",
  notfc="Planning **is not a forecast**: it uses the historical average of each day of the year.",
  tabs=["Map and timeline", "Recommended rotation by sector", "How it works"],
  fort="Fortnight", cells_ok="Suitable cells", mean_apt="Mean suitability", mean_alt="Mean altitude of suitable cells (m)",
  tip="Cell {celda}\nSuitability: {aptitud_txt}\nAltitude: {elev} m\nDistance to river: {dist_rio_m} m",
  mapcap="Each dot is a 1 km cell. Altitude comes from Copernicus DEM; climate from NASA POWER corrected for altitude.",
  pick="Choose a sector", how="How to choose", how_opts=["Example by altitude", "Coordinates"], alt="Approximate altitude (m)",
  lat="Latitude", lon="Longitude", sector="Sector", river="river at", altl="altitude",
  nofc="In this sector no crop of the catalogue completes its cycle with the average climate. Try another altitude or coordinate.",
  viable="Viable crops in this sector (next 12 months)",
  cols={"especie":"crop","siembra_desde":"sowing from","siembra_hasta":"sowing until","dias_a_cosecha_desde":"days to harvest",
        "cosecha_desde":"harvest from","cosecha_hasta":"harvest until","aptitud_media_tramo":"mean suitability"},
  rots="Recommended rotations", norot="With the viable crops of this sector no rotation of at least 2 crops from different families fits in 12 months. You can plant a single crop from the table above.",
  option="Option", score="score", rcols=["order","crop","sowing","harvest","days","suitability"], why="**Why:**", care="Care", harvest="Harvest",
  note="Care tips are guidance (PRELIMINARY) and must be validated by an agronomist. Dates use average climate, not a forecast.",
  ai_btn="Explain with AI (optional)", ai_info="To enable the AI explanation set the ANTHROPIC_API_KEY environment variable. The rotations above work without AI.",
  chart="Suitability by fortnight in this sector (first 6 months)",
 ),
 "es": dict(
  title="Rotación de cultivos con datos NASA (NASA POWER)",
  caption="Zona: Alto Cauca – Macizo Colombiano · celdas de 1 km · temperaturas de maíz, frijol y arveja verificadas con FAO; papa y ciclos son preliminares",
  opts="Opciones", period="Periodo", p_plan="Planificación (próximos 12 meses, clima promedio)", p_obs="Observado (últimos 12 meses)",
  species="Especie (para el mapa)", read="**Cómo leer el color:** verde = apto (puntaje ≥ 0,6); rojo = no apto.",
  notfc="Planificación **no es un pronóstico**: usa el promedio histórico de cada día del año.",
  tabs=["Mapa y línea de tiempo", "Rotación recomendada por sector", "Cómo funciona"],
  fort="Quincena", cells_ok="Celdas aptas", mean_apt="Aptitud media", mean_alt="Altitud media de celdas aptas (m)",
  tip="Celda {celda}\nAptitud: {aptitud_txt}\nAltitud: {elev} m\nDistancia a río: {dist_rio_m} m",
  mapcap="Cada punto es una celda de 1 km. La altitud viene de Copernicus DEM; el clima, de NASA POWER corregido por altitud.",
  pick="Elige un sector", how="Cómo elegir", how_opts=["Ejemplo por altitud", "Coordenadas"], alt="Altitud aproximada (m)",
  lat="Latitud", lon="Longitud", sector="Sector", river="río a", altl="altitud",
  nofc="En este sector ninguna especie del catálogo completa su ciclo con el clima promedio. Prueba otra altitud o coordenada.",
  viable="Especies viables en este sector (próximos 12 meses)",
  cols={"siembra_desde":"siembra desde","siembra_hasta":"siembra hasta","dias_a_cosecha_desde":"días a cosecha",
        "cosecha_desde":"cosecha desde","cosecha_hasta":"cosecha hasta","aptitud_media_tramo":"aptitud media"},
  rots="Rotaciones recomendadas", norot="Con las especies viables de este sector no se logra una rotación de al menos 2 cultivos de familias distintas dentro de 12 meses. Puedes sembrar una sola especie de la tabla de arriba.",
  option="Opción", score="puntaje", rcols=["orden","especie","siembra","cosecha","días","aptitud"], why="**Por qué:**", care="Cuidados", harvest="Cosecha",
  note="Los cuidados son orientativos (PRELIMINAR) y deben validarse con un agrónomo. Las fechas usan clima promedio, no un pronóstico.",
  ai_btn="Explicar con IA (opcional)", ai_info="Para activar la explicación con IA define la variable de entorno ANTHROPIC_API_KEY. Las rotaciones de arriba funcionan sin IA.",
  chart="Aptitud por quincena en este sector (primeros 6 meses)",
 ),
}
NOMBRE_EN = {"maiz": "maize", "frijol": "bean", "papa": "potato", "arveja": "pea"}
CUID_EN = {
 "maiz": ("Cereal demanding in nitrogen; a good crop after a legume",
          "Sow with enough soil moisture; split nitrogen fertilization; weed control in the first weeks; watch for fall armyworm.",
          "Physiological maturity of the grain; dry cob for grain or milky stage for fresh corn."),
 "frijol": ("Legume: fixes nitrogen and improves the soil for the next crop",
            "Well-drained soil, no waterlogging; avoid excess nitrogen; watch for rust and anthracnose in wet periods; staking for climbing types.",
            "When pods mature and dry; staggered picking for climbing types."),
 "papa": ("Solanaceae demanding in nutrients; avoid repeating solanaceous crops back to back",
          "Healthy or certified seed; hilling; watch for late blight (Phytophthora) in rainy weather; rotate with another family to break soil pests.",
          "When the foliage dries and the tuber skin sets."),
 "arveja": ("Cool-climate legume: fixes nitrogen",
            "Well-drained soil; staking for climbing varieties; watch for ascochyta, mildew and anthracnose in wet periods.",
            "Green (full pod) or dry depending on use."),
}


def motivo_en(m):
    import re
    r = [(r"Aptitud media ([\d.]+)", r"Mean suitability \1"),
         (r"Usa (\d+) de (\d+) dias \((\d+%)\)", r"Uses \1 of \2 days (\3)"),
         (r"Incluye leguminosa \(fija nitrogeno\)", "Includes a legume (fixes nitrogen)"),
         (r"No incluye leguminosa", "No legume included"),
         (r"Leguminosa antes de un cultivo exigente en nitrogeno", "Legume before a nitrogen-demanding crop"),
         (r"(\d+) familia\(s\) botanica\(s\) distintas", r"\1 different botanical family(ies)"),
         (r"Penalizacion ([\d.]+) por repetir familia", r"Penalty \1 for repeating a family")]
    for p, q in r:
        m = re.sub(p, q, m)
    return m


with st.sidebar:
    idioma = st.radio("Language / Idioma", ["English", "Español"])
L = "en" if idioma == "English" else "es"
t = TX[L]


def nm(e):
    return NOMBRE_EN.get(e, e) if L == "en" else e


st.title(t["title"])
st.caption(t["caption"])

with st.sidebar:
    st.header(t["opts"])
    periodo = st.radio(t["period"], [t["p_plan"], t["p_obs"]])
    modo = "planificacion" if periodo == t["p_plan"] else "reciente"
    esp = st.selectbox(t["species"], sorted(cultivos["especie"]), format_func=nm)
    st.markdown(t["read"])
    st.markdown(t["notfc"])

apt, fichas = cargar(modo)
apt_plan, fichas_plan = cargar("planificacion")
tab1, tab2, tab3 = st.tabs(t["tabs"])

# ---------------- Map ----------------
with tab1:
    quincenas = sorted(apt["quincena"].unique())
    q = st.select_slider(t["fort"], options=quincenas, format_func=lambda d: pd.Timestamp(d).strftime("%Y-%m-%d"))
    d = apt[(apt["especie"] == esp) & (apt["quincena"] == q)].merge(celdas, left_on="celda", right_on="celda_id")
    d["apta"] = d["aptitud"] >= UMBRAL
    d["color"] = d["aptitud"].apply(lambda v: [int(220 * (1 - v)), int(190 * v), 60, 170])
    d["aptitud_txt"] = d["aptitud"].round(2).astype(str)
    c1, c2, c3 = st.columns(3)
    c1.metric(t["cells_ok"], f"{d['apta'].mean():.0%}")
    c2.metric(t["mean_apt"], f"{d['aptitud'].mean():.2f}")
    c3.metric(t["mean_alt"], f"{d.loc[d['apta'], 'elev'].mean():.0f}" if d["apta"].any() else "–")
    st.pydeck_chart(pdk.Deck(
        layers=[pdk.Layer("ScatterplotLayer", d, get_position="[lon, lat]", get_fill_color="color", get_radius=520, pickable=True)],
        initial_view_state=pdk.ViewState(latitude=float(celdas["lat"].mean()), longitude=float(celdas["lon"].mean()), zoom=8.3),
        tooltip={"text": t["tip"]}))
    st.caption(t["mapcap"])

# ---------------- Rotation ----------------
with tab2:
    st.subheader(t["pick"])
    metodo = st.radio(t["how"], t["how_opts"], horizontal=True)
    con_ficha = set(fichas_plan["celda"].unique())
    cel = celdas[celdas["celda_id"].isin(con_ficha)]
    if metodo == t["how_opts"][0]:
        alt = st.select_slider(t["alt"], options=[900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300], value=1800)
        sector = cel.iloc[(cel["elev"] - alt).abs().argsort().iloc[0]]
    else:
        a, b = st.columns(2)
        lat = a.number_input(t["lat"], 2.0, 2.8, 2.40, 0.01)
        lon = b.number_input(t["lon"], -76.9, -76.2, -76.55, 0.01)
        sector = celdas.iloc[(((celdas["lat"] - lat) ** 2 + (celdas["lon"] - lon) ** 2)).argsort().iloc[0]]
    sid = sector["celda_id"]
    st.info(f"{t['sector']} **{sid}** · lat {sector['lat']:.3f}, lon {sector['lon']:.3f} · {t['altl']} {sector['elev']:.0f} m · "
            f"{t['river']} {sector['dist_rio_m']:.0f} m")
    fs = fichas_plan[fichas_plan["celda"] == sid]
    if len(fs) == 0:
        st.warning(t["nofc"])
    else:
        inicio = pd.Timestamp(apt_plan["quincena"].min())
        rots = mejores_rotaciones(fs, cultivos, inicio, dias_horizonte=365, max_ciclos=4, top=3)
        st.subheader(t["viable"])
        tabla = fs[["especie", "siembra_desde", "siembra_hasta", "dias_a_cosecha_desde", "cosecha_desde", "cosecha_hasta", "aptitud_media_tramo"]].copy()
        tabla["especie"] = tabla["especie"].map(nm)
        tabla = tabla.rename(columns=t["cols"])
        st.dataframe(tabla, hide_index=True, use_container_width=True)
        st.subheader(t["rots"])
        if not rots:
            st.warning(t["norot"])
        for i, r in enumerate(rots, 1):
            with st.expander(f"{t['option']} {i}: " + " → ".join(nm(p["especie"]) for p in r["secuencia"]) + f"   ({t['score']} {r['puntaje']:.2f})", expanded=(i == 1)):
                st.dataframe(pd.DataFrame([dict(zip(t["rcols"], [n, nm(p["especie"]), p["siembra"].date(), p["cosecha"].date(),
                                                                  p["dias"], round(p["aptitud"], 2)])) for n, p in enumerate(r["secuencia"], 1)]),
                             hide_index=True, use_container_width=True)
                mot = [motivo_en(m) for m in r["motivos"]] if L == "en" else r["motivos"]
                st.markdown(t["why"] + " " + " · ".join(mot))
                for p in r["secuencia"]:
                    e = p["especie"]
                    if L == "en" and e in CUID_EN:
                        rol, cu, co = CUID_EN[e]
                        st.markdown(f"- **{nm(e)}** ({rol}). {t['care']}: {cu} {t['harvest']}: {co}")
                    elif e in cuidados.index:
                        c = cuidados.loc[e]
                        st.markdown(f"- **{e}** ({c['rol_en_rotacion']}). {t['care']}: {c['cuidados_clave']} {t['harvest']}: {c['cosecha']}")
        if rots:
            st.caption(t["note"])
            if st.button(t["ai_btn"]):
                p = prompt_ia(sid, rots, cuidados.reset_index().to_dict("records"))
                if L == "en":
                    p += "\nAnswer in English."
                txt = explicar_con_ia(p)
                if txt:
                    st.markdown(txt)
                else:
                    st.info(t["ai_info"])
        ap_s = apt_plan[apt_plan["celda"] == sid].pivot(index="quincena", columns="especie", values="aptitud")
        ap_s.columns = [nm(c) for c in ap_s.columns]
        st.subheader(t["chart"])
        st.line_chart(ap_s)

# ---------------- How it works ----------------
with tab3:
    if L == "en":
        st.markdown("""
### What this tool does
It shows in which sectors of the area each crop can be planted and proposes rotations that protect the soil, based on **NASA observations**.

### Where the data comes from
- **Climate:** NASA POWER (MERRA-2 reanalysis): daily temperature, rain, humidity, wind and radiation since 1981. Cells of ~50 km. https://power.larc.nasa.gov/
- **Altitude:** Copernicus DEM GLO-30 (30 m). Used to correct temperature with height (−0.0065 °C per metre).
- **Rivers:** HydroRIVERS (HydroSHEDS). The distance from each cell to the nearest river is used.
- **Crops:** catalogue with temperature ranges, growing-degree-day cycle and Kc (FAO-56). Temperatures of **maize** (FAO Ecocrop), **bean** and **pea** (FAO Land & Water) are verified; potato, base temperatures, degree-days and cycle lengths are own estimates (**preliminary**).

### Calculation steps
1. For each day and cell the **evapotranspiration** (FAO-56 Penman–Monteith) and the water each crop needs are computed.
2. **Suitability score (0–1)** = the lower of the temperature score and the water score (law of the minimum, as in Ecocrop).
3. A day is **suitable** if the score ≥ 0.6.
4. **Permanence rule:** a crop gets a *record* in a sector if there is a continuous run of suitable days accumulating at least 95 % of the growing-degree-days of its cycle (±5 % tolerance).
5. **Rotations:** the crops with a record in the sector are combined into sequences of 2 to 4 crops, never repeating a family back to back, and scored by suitability, use of the year, legume, nitrogen and diversity.

### Limitations (important)
- NASA POWER has low resolution and rain is its most uncertain variable; it still needs calibration with IDEAM stations.
- Soil is not yet part of the score.
- FAO values are global and do not reflect Andean practice: high-altitude sectors lose coverage.
- The 0.6 threshold and the rotation weights are design criteria that must be validated.
- *Planning* mode is not a weather forecast.
""")
    else:
        st.markdown("""
### Qué hace esta herramienta
Indica en qué sectores de la zona puede sembrarse cada especie y propone rotaciones que cuidan el suelo, a partir de **observaciones de la NASA**.

### De dónde salen los datos
- **Clima:** NASA POWER (reanálisis MERRA-2): temperatura, lluvia, humedad, viento y radiación diarios desde 1981. Celdas de ~50 km. https://power.larc.nasa.gov/
- **Altitud:** Copernicus DEM GLO-30 (30 m). Sirve para corregir la temperatura por altura (−0,0065 °C por metro).
- **Ríos:** HydroRIVERS (HydroSHEDS). Se usa la distancia de cada celda al río más cercano.
- **Cultivos:** catálogo con rangos de temperatura, ciclo en grados-día y coeficiente Kc (FAO-56). Las temperaturas de **maíz** (FAO Ecocrop), **frijol** y **arveja** (FAO Land & Water) están verificadas; papa, temperaturas base, grados-día y duración del ciclo son estimaciones propias (**preliminares**).

### Pasos del cálculo
1. Cada día y celda se calcula la **evapotranspiración** (FAO-56 Penman–Monteith) y el agua que necesita cada cultivo.
2. **Puntaje de aptitud (0–1)** = el menor entre el puntaje de temperatura y el de agua (ley del mínimo, como en Ecocrop).
3. Un día es **apto** si el puntaje ≥ 0,6.
4. **Regla de permanencia:** una especie recibe *ficha* en un sector si hay un tramo continuo de días aptos que acumula al menos el 95 % de los grados-día de su ciclo (tolerancia ±5 %).
5. **Rotaciones:** se combinan las especies con ficha del sector en secuencias de 2 a 4 cultivos, sin repetir familia seguida, y se puntúan por aptitud, uso del año, leguminosa, nitrógeno y diversidad.

### Limitaciones (importantes)
- NASA POWER tiene baja resolución y la lluvia es su variable más incierta; falta calibrar con estaciones del IDEAM.
- El suelo todavía no entra en el puntaje.
- Los valores FAO son globales y no reflejan la práctica andina: los sectores altos pierden cobertura.
- El umbral de 0,6 y los pesos de la rotación son criterios de diseño que deben validarse.
- El modo *Planificación* no es un pronóstico del clima.
""")
