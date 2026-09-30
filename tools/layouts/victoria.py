#!/usr/bin/env python3
"""Victoria (940GZZLUVIC) from TfL station layout diagram V047-02 (topology; dimensions estimated).
Victoria-line ticket hall (exits A and F, to the main line station) -> escalators down (~6.4 m) to the interchange concourse beside the
District & Circle platforms 1 & 2 (6.4 m below street) -> a second, longer bank down to Victoria line platforms 3 & 4 (17.9 m).
Separate District & Circle ticket hall (exits B and C) with stairs down to the same concourse."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUVIC", "Victoria, from TfL layout diagram V047-02 (topology; dimensions estimated): Victoria line ticket hall (A, F), D&C ticket hall (B, C), interchange concourse, D&C platforms 1-2 at 6.4 m, Victoria line platforms 3-4 at 17.9 m",
     halls=[
         {"id": "hall_vl", "x0": -12, "x1": 12, "gates": 12, "doors": [{"ref": "A", "name": "Victoria Station"}, {"ref": "F", "name": "Victoria Station"}]},
         {"id": "hall_dc", "x0": -36, "x1": -20, "gates": 8, "doors": [{"ref": "B"}, {"ref": "C"}]},
     ],
     landings=[
         {"id": "conc", "depth": 6.4, "w": 44, "d": 22, "parents": [{"from": "hall_vl", "lanes": [1, -1, 1]}, {"from": "hall_dc", "lanes": [1, -1], "stairs": True}]},
         {"id": "vl_low", "depth": 17.9, "w": 36, "d": 16, "parents": [{"from": "conc", "lanes": [1, -1, -1, 1]}]},
     ],
     modules=[
         {"attach": "conc", "group": "ss", "faces": [["ss:Eastbound", 0], ["ss:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "vl_low", "group": "victoria", "faces": [["victoria:Northbound", 0], ["victoria:Southbound", 0]], "lane": 0, "corr": 12},
     ])
