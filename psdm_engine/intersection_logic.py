import json
import geopandas as gpd
from shapely.geometry import shape, Point

_WORLD_URL = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"

def calculate_spatial_score(plonk_geojson: dict, cognitive_countries: list) -> dict:
    world = gpd.read_file(_WORLD_URL)

    # Match Gemini's candidates by ISO code, falling back to the English name.
    # ADM0_A3 is checked too because ISO_A3 is "-99" for a few countries (e.g. France).
    codes = {c["iso_a3"].strip().upper() for c in cognitive_countries if c["iso_a3"]}
    names = {c["name"].strip().lower() for c in cognitive_countries if c["name"]}
    matched = world[
        world["ADM0_A3"].str.upper().isin(codes)
        | world["ISO_A3"].str.upper().isin(codes)
        | world["ADMIN"].str.lower().isin(names)
        | world["NAME"].str.lower().isin(names)
        | world["NAME_LONG"].str.lower().isin(names)
    ]

    plonk_geom = shape(plonk_geojson["geometry"])

    intersecting = []
    confidence = "low"

    for _, row in matched.iterrows():
        if row.geometry and row.geometry.contains(plonk_geom):
            intersecting.append(row["ADMIN"])
            confidence = "high"
        elif row.geometry and row.geometry.intersects(plonk_geom):
            intersecting.append(row["ADMIN"])
            if confidence != "high":
                confidence = "medium"

    lat = plonk_geojson["properties"]["latitude"]
    lon = plonk_geojson["properties"]["longitude"]

    return {
        "latitude": lat,
        "longitude": lon,
        "confidence": confidence,
        "intersecting_countries": intersecting,
        "cognitive_candidates": [c["name"] or c["iso_a3"] for c in cognitive_countries],
    }
