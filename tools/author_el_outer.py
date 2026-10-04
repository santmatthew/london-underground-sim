#!/usr/bin/env python3
"""The looks of the Elizabeth line's outer (surface) stations, authored from reference photographs (Wikimedia Commons, private under build/refs_dress/surface, never committed; fetch with
tools/fetch_surface_refs.py build/el_queries.txt). Writes data/station_character_el.json, which StationCharacter merges into its open-air platform styles ("open_styles" / "surface_overrides").

What a photograph can give is the roof over the platform (kind, how much of the platform it covers, the colour of its columns and fascia), the wall across the track and the platform front,
and the lamp standards. The layout of the platform (the sim builds every outer station as one island platform with its entrance at the west end) and the footbridges are not from the photographs.
  python3 tools/author_el_outer.py
"""
import json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "station_character_el.json")

WHITE = [0.93, 0.93, 0.91]
CREAM = [0.95, 0.93, 0.86]
GREY = [0.62, 0.64, 0.67]
LGREY = [0.80, 0.82, 0.84]
DGREY = [0.26, 0.27, 0.30]
BLUE = [0.14, 0.24, 0.52]
RED = [0.72, 0.15, 0.11]
TEAL = [0.15, 0.52, 0.58]

# name: (photo notes, style). "base" = rail_valanced; keys as in the open_styles of data/station_character.json
S = {
    "Acton Main Line": ("paved platforms, no canopy: a small glazed shelter, white railings, tall lamp masts, footbridge",
                        {"canopy": "slab", "roof_h": 3.2, "spans": [[0.03, 0.09]], "col": "round", "col_main": GREY, "col_band": BLUE, "fascia": LGREY, "wall": "concrete", "front": "brick_stock", "lamps": "cctv"}),
    "West Ealing": ("a long flat canopy on round columns with dark bands; the other platform bare",
                    {"canopy": "slab", "roof_h": 3.8, "spans": [[0.0, 0.42]], "col": "round", "col_main": GREY, "col_band": [0.45, 0.12, 0.16], "fascia": LGREY, "wall": "concrete", "front": "brick_blue", "lamps": "cctv"}),
    "Hanwell": ("Brunel-era waiting sheds in cream with maroon, no canopy, black iron fence, ornate lamp standards",
                {"canopy": "gable", "valance": "none", "rise": 0.8, "roof_h": 3.3, "spans": [[0.34, 0.41]], "col": "iron", "col_main": CREAM, "col_band": [0.45, 0.16, 0.12], "fascia": CREAM,
                 "soffit": "flat:#d8cdb5", "top": "flat:#4a3f3a", "wall": "brick_red", "front": "brick_blue", "lamps": "victorian"}),
    "Southall": ("a long cast-iron canopy with a scalloped white valance and dark ironwork",
                 {"canopy": "valanced", "valance": "scallop", "roof_h": 3.9, "spans": [[0.0, 0.52]], "col": "iron", "col_main": [0.14, 0.14, 0.16], "col_band": [0.14, 0.14, 0.16], "fascia": WHITE,
                  "soffit": "timber_slab", "wall": "brick_red", "front": "brick_blue", "lamps": "victorian"}),
    "Hayes & Harlington": ("the rebuilt station: a white pitched canopy on steel columns, dark brick platform fronts",
                           {"canopy": "gable", "valance": "none", "rise": 1.1, "roof_h": 3.8, "spans": [[0.03, 0.55]], "col": "square", "col_main": [0.74, 0.76, 0.79], "col_band": [0.36, 0.38, 0.41], "fascia": WHITE,
                            "soffit": "flat:#e8e8e6", "top": "flat:#c9ccd0", "wall": "brick_blue", "front": "brick_blue", "lamps": "cctv"}),
    "West Drayton": ("a Brunel-style train shed at one end over a pavilion, bare platform beyond; yellow stock brick, purple railings",
                     {"canopy": "gable", "valance": "none", "rise": 1.2, "roof_h": 4.4, "spans": [[0.0, 0.16]], "col": "iron", "col_main": WHITE, "col_band": DGREY, "fascia": [0.55, 0.58, 0.60],
                      "soffit": "flat:#d7d3c8", "top": "flat:#6a6e72", "wall": "brick_stock", "front": "brick_stock", "lamps": "cctv"}),
    "Iver": ("white railings, two small white pitched-roof cabins, no canopy",
             {"canopy": "gable", "valance": "none", "rise": 0.9, "roof_h": 3.2, "spans": [[0.07, 0.11], [0.30, 0.34]], "col": "iron", "col_main": WHITE, "col_band": WHITE, "fascia": WHITE,
              "soffit": "flat:#e6e3da", "top": "flat:#7a7f84", "wall": "brick_stock", "front": "brick_blue", "lamps": "cctv"}),
    "Langley": ("the Victorian station building with a white canopy along it",
                {"canopy": "valanced", "valance": "scallop", "roof_h": 3.6, "spans": [[0.04, 0.34]], "col": "iron", "col_main": CREAM, "col_band": CREAM, "fascia": CREAM,
                 "soffit": "flat:#e9e5d6", "top": "flat:#4c4a48", "wall": "brick_red", "front": "brick_stock", "lamps": "victorian"}),
    "Slough": ("a long flat canopy on square white concrete columns",
               {"canopy": "slab", "roof_h": 3.6, "spans": [[0.0, 0.48]], "col": "square", "col_main": [0.82, 0.84, 0.84], "col_band": [0.82, 0.84, 0.84], "fascia": [0.85, 0.86, 0.86], "wall": "brick_red", "front": "brick_stock", "lamps": "cctv"}),
    "Burnham": ("two small modern shelters on a bare platform, grey lamp standards",
                {"canopy": "slab", "roof_h": 3.0, "spans": [[0.12, 0.20], [0.42, 0.48]], "col": "round", "col_main": DGREY, "col_band": DGREY, "fascia": [0.62, 0.63, 0.66], "wall": "brick_red", "front": "brick_stock", "lamps": "cctv"}),
    "Taplow": ("a bare platform with white railings and a small brick shelter; the Brunel brick building behind",
               {"canopy": "gable", "valance": "none", "rise": 0.9, "roof_h": 3.2, "spans": [[0.30, 0.36]], "col": "iron", "col_main": WHITE, "col_band": WHITE, "fascia": WHITE,
                "soffit": "flat:#e6e3da", "top": "flat:#5d5a58", "wall": "brick_red", "front": "brick_stock", "lamps": "cctv"}),
    "Maidenhead": ("valanced canopies with white and dark boards on pale columns with blue bases",
                   {"canopy": "valanced", "valance": "saw", "roof_h": 4.0, "spans": [[0.0, 0.50]], "col": "iron", "col_main": [0.9, 0.92, 0.95], "col_band": [0.12, 0.2, 0.42], "fascia": WHITE,
                    "soffit": "ceiling", "wall": "brick_red", "front": "brick_stock", "lamps": "cctv"}),
    "Twyford": ("a dark flat canopy over the booking hall end, bare platform beyond",
                {"canopy": "slab", "roof_h": 3.5, "spans": [[0.0, 0.32]], "col": "square", "col_main": [0.55, 0.58, 0.62], "col_band": DGREY, "fascia": [0.30, 0.32, 0.36],
                 "soffit": "flat:#4a4a4e", "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
    "Forest Gate": ("red-painted iron canopy columns with blue bases and a white flat roof edge; white railings",
                    {"canopy": "valanced", "valance": "none", "roof_h": 3.8, "spans": [[0.0, 0.38]], "col": "iron", "col_main": RED, "col_band": BLUE, "fascia": WHITE,
                     "soffit": "timber_slab", "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
    "Manor Park": ("two small flat shelters, long concrete walls with white railings, lamp masts",
                   {"canopy": "slab", "roof_h": 3.2, "spans": [[0.02, 0.10], [0.50, 0.58]], "col": "round", "col_main": LGREY, "col_band": LGREY, "fascia": WHITE, "wall": "concrete", "front": "brick_blue", "lamps": "cctv"}),
    "Ilford": ("a long canopy of cast-iron columns painted white and blue, dark timber soffit",
               {"canopy": "valanced", "valance": "saw", "roof_h": 4.2, "spans": [[0.0, 0.62]], "col": "iron", "col_main": [0.88, 0.90, 0.94], "col_band": [0.20, 0.32, 0.62], "fascia": [0.90, 0.90, 0.90],
                "soffit": "timber_slab", "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
    "Seven Kings": ("a bare platform with white railings and one small curved-roof shelter",
                    {"canopy": "slab", "roof_h": 3.0, "spans": [[0.38, 0.44]], "col": "round", "col_main": LGREY, "col_band": LGREY, "fascia": GREY, "wall": "concrete", "front": "brick_blue", "lamps": "cctv"}),
    "Goodmayes": ("flagged platform, planting, no canopy but a small shelter",
                  {"canopy": "slab", "roof_h": 3.0, "spans": [[0.30, 0.34]], "col": "round", "col_main": GREY, "col_band": GREY, "fascia": LGREY, "wall": "brick_red", "front": "brick_stock", "planters": "box", "lamps": "cctv"}),
    "Chadwell Heath": ("a long valanced canopy on pale blue columns, red brick wall behind",
                       {"canopy": "valanced", "valance": "scallop", "roof_h": 3.8, "spans": [[0.0, 0.46]], "col": "iron", "col_main": [0.5, 0.62, 0.85], "col_band": [0.5, 0.62, 0.85], "fascia": [0.9, 0.9, 0.9],
                        "soffit": "ceiling", "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
    "Gidea Park": ("two small modern shelters, curved steel masts",
                   {"canopy": "slab", "roof_h": 3.1, "spans": [[0.12, 0.18], [0.56, 0.62]], "col": "round", "col_main": [0.45, 0.50, 0.55], "col_band": [0.45, 0.50, 0.55], "fascia": LGREY, "wall": "brick_stock", "front": "brick_blue", "lamps": "cctv"}),
    "Romford": ("a bare platform with tall poles beside a brick wall",
                {"canopy": "slab", "roof_h": 3.4, "spans": [[0.0, 0.30]], "col": "square", "col_main": [0.8, 0.82, 0.84], "col_band": [0.8, 0.82, 0.84], "fascia": LGREY, "wall": "brick_red", "front": "brick_stock", "lamps": "cctv"}),
    "Harold Wood": ("a small canopy by the red-brick buildings, red lamp standards",
                    {"canopy": "timber", "valance": "scallop", "roof_h": 3.2, "spans": [[0.12, 0.20]], "col": "iron", "col_main": [0.75, 0.20, 0.12], "col_band": [0.75, 0.20, 0.12], "fascia": [0.9, 0.88, 0.82],
                     "soffit": "timber_slab", "wall": "brick_red", "front": "brick_blue", "lamps": "victorian"}),
    "Brentwood": ("a timber canopy with a scalloped valance on teal columns",
                  {"canopy": "valanced", "valance": "scallop", "roof_h": 3.8, "spans": [[0.0, 0.40]], "col": "iron", "col_main": TEAL, "col_band": TEAL, "fascia": [0.9, 0.92, 0.9],
                   "soffit": "timber_slab", "wall": "brick_red", "front": "brick_stock", "lamps": "victorian"}),
    "Maryland": ("a white flat canopy beside the brick buildings",
                 {"canopy": "slab", "roof_h": 3.5, "spans": [[0.0, 0.34]], "col": "round", "col_main": [0.82, 0.82, 0.80], "col_band": [0.82, 0.82, 0.80], "fascia": WHITE, "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
    "Shenfield": ("a long white pitched canopy along the station building",
                  {"canopy": "gable", "valance": "none", "rise": 0.9, "roof_h": 3.9, "spans": [[0.0, 0.36]], "col": "iron", "col_main": [0.92, 0.92, 0.90], "col_band": [0.92, 0.92, 0.90], "fascia": WHITE,
                   "soffit": "flat:#e3e0d4", "top": "flat:#c9ccd0", "wall": "brick_red", "front": "brick_blue", "lamps": "cctv"}),
}


# The Heathrow stations (underground; their Elizabeth line platforms are shared with Heathrow Express), from Commons photographs (Terminal 4 platforms 1 / 2, Terminal 5 platforms 3 / 4,
# Terminals 2 & 3 platform 2): T4 and T2 & 3 are bored tunnels, T5 a box with grey stone cladding lit with a violet wash.
HEATHROW = {
    "Heathrow Terminal 4": {"bored": True, "wall": "tile_sq_grey", "floor": "floor_slab", "stripes": [[0.0, 0.25, "grey_dk", 0]], "light": [1.0, 0.94, 0.84], "ribs": {"ink": "grey_dk", "every": 2.2, "w": 0.55}},
    "Heathrow Terminals 2 & 3": {"bored": True, "wall": "el_dark", "floor": "floor_slab", "stripes": [], "light": [1.35, 1.14, 0.92], "ribs": {"ink": "ink_brown", "every": 1.8, "w": 0.3}},
    "Heathrow Terminal 5": {"bored": False, "wall": "panel_white", "floor": "floor_stone", "ceil": "concrete", "stripes": [[0.0, 0.2, "grey_dk", 0]], "light": [0.82, 0.80, 1.0]},
}


def main():
    styles = {"_comment": "Open-air platform styles of the Elizabeth line's outer stations, authored from private reference photographs by tools/author_el_outer.py (merged into open_styles by StationCharacter)."}
    over = {}
    for name, (notes, st) in S.items():
        d = {"floor": "floor_slab", "front": "brick_stock", "wall": "brick_stock"}
        d.update(st)
        styles[name] = d
        over[name] = name
    json.dump({"open_styles": styles, "surface_overrides": over, "elizabeth_heathrow": HEATHROW, "elizabeth_bored": [k for k, v in HEATHROW.items() if v.get("bored")]}, open(OUT, "w"), indent=1)
    print("wrote", OUT, len(S), "stations")


if __name__ == "__main__":
    main()
