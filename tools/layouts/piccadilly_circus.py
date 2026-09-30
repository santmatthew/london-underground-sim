#!/usr/bin/env python3
"""Piccadilly Circus (940GZZLUPCC) from TfL station layout diagram P063-02 (topology; dimensions estimated).
One large circular ticket hall fed by subways 1-4 with seven street exits, a bank of five escalators (numbers 7-11) down to the Bakerloo
platforms (28.0 m below street), and a short link down to the Piccadilly line platforms (32.3 m)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUPCC", "Piccadilly Circus, from TfL layout diagram P063-02 (topology; dimensions estimated): circular ticket hall with 7 exits, 5 escalators to the Bakerloo platforms (28.0 m), link to the Piccadilly line platforms (32.3 m)",
     halls=[
         {"id": "hall_main", "x0": -20, "x1": 20, "gates": 16, "doors": [{"ref": str(i)} for i in range(1, 8)]},
     ],
     landings=[
         {"id": "land_b", "depth": 28.0, "w": 44, "d": 20, "parents": [{"from": "hall_main", "lanes": [1, -1, 1, -1, 1]}]},
         {"id": "land_p", "depth": 32.3, "w": 36, "d": 14, "parents": [{"from": "land_b", "lanes": [1, -1], "stairs": True}]},
     ],
     modules=[
         {"attach": "land_b", "group": "bakerloo", "faces": [["bakerloo:Northbound", 0], ["bakerloo:Southbound", 0]], "lane": 0, "corr": 12},
         {"attach": "land_p", "group": "piccadilly", "faces": [["piccadilly:Eastbound", 0], ["piccadilly:Westbound", 0]], "lane": 0, "corr": 12},
     ])
