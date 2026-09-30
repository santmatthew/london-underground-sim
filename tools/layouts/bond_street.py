#!/usr/bin/env python3
"""Bond Street (940GZZLUBND) from TfL station layout diagram C125-02 (topology; dimensions estimated).
Ticket hall (exits A-C) -> two escalator banks to the Central line platforms 1 & 2 (22.2 m) -> intermediate concourse -> lower concourse and the
Jubilee line platforms 3 & 4 (32.0 m).  The diagram only letters the exits; the streets are the ones the station opens onto."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUBND", "Bond Street, from TfL layout diagram C125-02 (topology; dimensions estimated): ticket hall, Central 22.2 m, Jubilee 32.0 m",
     halls=[
         {"id": "hall_main", "x0": -14, "x1": 14, "gates": 12, "doors": [{"name": "Oxford Street"}, {"name": "Davies Street"}, {"name": "Marylebone Lane"}]},
     ],
     landings=[
         {"id": "conc_c", "depth": 22.2, "w": 40, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1, 1]}]},
         {"id": "conc_j", "depth": 32.0, "w": 36, "d": 14, "parents": [{"from": "conc_c", "lanes": [1, -1, 1]}]},
     ],
     modules=[
         {"attach": "conc_c", "group": "central", "faces": [["central:Eastbound", 0], ["central:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_j", "group": "jubilee", "faces": [["jubilee:Northbound", 0], ["jubilee:Southbound", 0]], "lane": 0, "corr": 12},
     ])
