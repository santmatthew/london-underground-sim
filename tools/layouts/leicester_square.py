#!/usr/bin/env python3
"""Leicester Square (940GZZLULSQ) from TfL station layout diagram N107-02 (topology; dimensions estimated).
Round ticket hall (exits A-D) -> escalators 4-6 down to the Northern line middle concourse (27.4 m) -> the interchange subway down to the
Piccadilly line middle concourse (32.3 m).  In the real station escalators 1-3 also run straight from the hall to the Piccadilly concourse; the
compiler places every room once, so that second bank is folded into the chain (same total drop)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLULSQ", "Leicester Square, from TfL layout diagram N107-02 (topology; dimensions estimated): round ticket hall, Northern concourse 27.4 m, Piccadilly concourse 32.3 m via the interchange subway",
     halls=[
         {"id": "hall_main", "x0": -14, "x1": 14, "gates": 10, "doors": [{"ref": str(i)} for i in range(1, 5)]},
     ],
     landings=[
         {"id": "conc_n", "depth": 27.4, "w": 40, "d": 18, "parents": [{"from": "hall_main", "lanes": [1, -1, 1]}]},
         {"id": "conc_p", "depth": 32.3, "w": 36, "d": 14, "parents": [{"from": "conc_n", "lanes": [1, -1], "stairs": True}]},
     ],
     modules=[
         {"attach": "conc_n", "group": "northern", "faces": [["northern:Northbound", 0], ["northern:Southbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_p", "group": "piccadilly", "faces": [["piccadilly:Eastbound", 0], ["piccadilly:Westbound", 0]], "lane": 0, "corr": 12},
     ])
