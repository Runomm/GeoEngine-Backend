import json
import geopandas as gpd
from shapely.geometry import shape, Point

_WORLD_URL = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"

def calculate_spatial_score(plonk_geojson: dict, cognitive_countries: list) -> dict:
    world = gpd.read_file(_WORLD_URL)
    # CDN dataset uses 'ADMIN' for country name
    world = world.rename(columns={"ADMIN": "name"})

    matched = world[world["name"].isin(cognitive_countries)]

    plonk_geom = shape(plonk_geojson["geometry"])

    intersecting = []
    confidence = "low"

    for _, row in matched.iterrows():
        if row.geometry and row.geometry.contains(plonk_geom):
            intersecting.append(row["name"])
            confidence = "high"
        elif row.geometry and row.geometry.intersects(plonk_geom):
            intersecting.append(row["name"])
            if confidence != "high":
                confidence = "medium"

    lat = plonk_geojson["properties"]["latitude"]
    lon = plonk_geojson["properties"]["longitude"]

    return {
        "latitude": lat,
        "longitude": lon,
        "confidence": confidence,
        "intersecting_countries": intersecting,
        "cognitive_candidates": cognitive_countries,
    }
