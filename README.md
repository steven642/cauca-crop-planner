# Cauca Crop Planner

**NASA Space Apps Challenge 2026 – "Adapting farms with NASA data"**

Decision-support app that overlays **NASA POWER** climate data, a **Copernicus DEM** and the **HydroRIVERS** river network on the Alto Cauca – Macizo Colombiano region (Colombia, lat 2.0–2.8, lon −76.9 to −76.2; 6,942 cells of 1 km). It checks where and when maize, bean, potato and pea can be planted, builds a biweekly timeline, and recommends crop rotations per sector.

The interface has an **English / Español** switch in the sidebar (English by default).

## Live demo
https://cauca-crop-planner-h68n3xznrxlhtjbwpzh3vd.streamlit.app

## What it does
1. **Climate:** NASA POWER (MERRA-2) daily data, 4 nodes of ~50 km, nearest node per cell, temperature corrected for altitude with the DEM (−0.0065 °C/m).
2. **Suitability:** Ecocrop-style temperature trapezoid + FAO-56 Penman–Monteith water balance; law of the minimum; a day is suitable if score ≥ 0.6.
3. **Permanence rule:** a crop is viable only if a continuous run of suitable days accumulates ≥ 95 % (±5 % tolerance) of its growing-degree-days.
4. **Rotation optimizer:** rule-based, 2–4 crops in 12 months, no repeated family back to back, legume before nitrogen-demanding crops.

## Run locally
```
pip install -r requirements.txt
python -m streamlit run app.py
```
Precomputed results are included in `salidas/` (`reciente` = last observed months, `planificacion` = next 12 months with average climate).

To regenerate the results after changing `data/cultivos_base.csv`:
```
python -m src.actualizar                     # download/update NASA POWER (needs internet)
python -m src.run --clima data/power_diario.csv --celdas data/celdas.csv
```
`requirements-dev.txt` adds the libraries needed to rebuild the cell grid from a DEM and rivers (`src/construir_celdas.py`).

## Data sources
- NASA POWER (MERRA-2): https://power.larc.nasa.gov/
- Copernicus DEM GLO-30: https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model
- HydroRIVERS / HydroSHEDS: https://www.hydrosheds.org/products/hydrorivers
- FAO Irrigation and Drainage Paper 56: https://www.fao.org/4/x0490e/x0490e00.htm
- FAO Ecocrop (maize, id 2175): https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2175
- FAO Land & Water crop information: https://www.fao.org/land-water/databases-and-software/crop-information
- McMaster & Wilhelm (1997), growing degree days, Agric. For. Meteorol. 87:291–300

## Crop parameters and limits
- Temperatures for **maize** (FAO Ecocrop), **bean** and **pea** (FAO Land & Water) are verified. **Potato**, base temperatures, degree-days and cycle lengths are own estimates (preliminary). The previous catalogue is kept in `data/cultivos_base_preliminar.csv`.
- FAO values are global; high-altitude sectors lose coverage compared with Andean practice.
- NASA POWER cells are ~50 km: 1–3 °C temperature bias is possible in the Andes and rainfall is uncalibrated (no IDEAM stations yet).
- Planning mode uses the historical mean of each day of the year; **it is not a forecast**.
- Soil, slope, frost, pests and markets are not modelled. Care tips are guidance only and must be validated by an agronomist.

## Use of AI
Claude (Anthropic) assisted in developing the code, the slides and the documentation. The app logic is rule-based; an optional button can explain results with an AI model if `ANTHROPIC_API_KEY` is set.

## Repository contents
- `app.py` – Streamlit interface · `src/` – data download, suitability, rotation logic · `data/` – cells and crop catalogue · `salidas/` – precomputed results · `tests/` – unit tests
- `Cauca_Crop_Planner_NASA_SpaceApps2026.pptx` – project slides · `Cauca_Crop_Planner_codigo.m` – all Python code in one readable file
