#!/usr/bin/env python3
"""Builds the schematic ("Beck style") Tube diagram from the real network: data/network.json -> data/tube_diagram.json.

Stations start at their real positions, warped so the centre is magnified and the outskirts compressed; an optimiser then pulls every edge
towards a multiple of 45 degrees (while keeping the geometry roughly where it was), the result is snapped to a grid, edges are drawn as
octilinear polylines, and labels are placed round each station.  Rendered to build/diagram/*.png for inspection; the game draws the JSON.

usage: python3 tools/build_diagram.py [--png]          (a full relayout; the saved grid in build/diagram/G.npy is reused unless --relayout)
       python3 tools/build_diagram.py --add [--png]    (stations of data/network.json that data/tube_diagram.json lacks are placed next to the existing ones, which stay put)
"""
import json, math, os, sys, collections
import numpy as np
from scipy.optimize import minimize

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NET = json.load(open(os.path.join(ROOT, "data", "network.json")))
S = NET["stations"]
LINES = NET["lines"]
ids = list(S.keys())
ix = {k: i for i, k in enumerate(ids)}
N = len(ids)


def build_edges():
    e = collections.defaultdict(set)
    seqs = []
    for lid, l in LINES.items():
        for svc in l["services"]:
            st = svc["stops"]
            seqs.append((lid, st))
            for a, b in zip(st, st[1:]):
                e[tuple(sorted((a, b)))].add(lid)
    return e, seqs


EDGES, SEQS = build_edges()
E = [(ix[a], ix[b]) for (a, b) in EDGES]
E_LINES = [sorted(EDGES[k]) for k in EDGES]
LINKS = [(ix[l["a"]], ix[l["b"]]) for l in NET["links"]]
P_GEO = np.array([[S[k]["x"], S[k]["y"]] for k in ids], dtype=float)


def warp(P, gamma=0.62, scale=None):
    """radial warp about the centre of Zone 1: r -> r^gamma (centre magnified, outskirts compressed)"""
    z1 = np.array([i for i, k in enumerate(ids) if S[k]["zone"] == 1])
    c = np.median(P[z1], axis=0)
    v = P - c
    r = np.linalg.norm(v, axis=1) + 1e-9
    r2 = r ** gamma
    Q = c + v * (r2 / r)[:, None]
    return Q, c


def energy(X_flat, P1, w):
    X = X_flat.reshape(-1, 2)
    g = np.zeros_like(X)
    E_tot = 0.0
    a = np.array([e[0] for e in E])
    b = np.array([e[1] for e in E])
    v = X[b] - X[a]
    r2 = (v ** 2).sum(1) + 1e-12
    r = np.sqrt(r2)
    th = np.arctan2(v[:, 1], v[:, 0])
    # octilinear alignment
    f = 0.5 * (1 - np.cos(8 * th))
    E_tot += w["ang"] * f.sum()
    dth = 4 * np.sin(8 * th)
    gv = w["ang"] * dth[:, None] * np.stack([-v[:, 1] / r2, v[:, 0] / r2], 1)
    np.add.at(g, b, gv)
    np.add.at(g, a, -gv)
    # edge length: keep near the target (warped geographic length, clamped)
    Lt = np.clip(np.linalg.norm(P1[b] - P1[a], axis=1), w["lmin"], w["lmax"])
    dl = r - Lt
    E_tot += w["len"] * (dl ** 2).sum()
    gl = w["len"] * 2 * dl[:, None] * v / r[:, None]
    np.add.at(g, b, gl)
    np.add.at(g, a, -gl)
    # anchor to the warped geographic layout
    dp = X - P1
    E_tot += w["anchor"] * (dp ** 2).sum()
    g += w["anchor"] * 2 * dp
    # repulsion between stations that are too close
    D = X[:, None, :] - X[None, :, :]
    dist = np.sqrt((D ** 2).sum(2)) + 1e-9
    np.fill_diagonal(dist, 1e9)
    viol = np.clip(w["dmin"] - dist, 0, None)
    E_tot += w["rep"] * 0.5 * (viol ** 2).sum()
    coef = -w["rep"] * viol / dist
    g += 2 * (coef[:, :, None] * D).sum(1)
    return E_tot, g.ravel()


def optimise(P1, stages):
    X = P1.copy()
    for w in stages:
        res = minimize(energy, X.ravel(), args=(P1, w), jac=True, method="L-BFGS-B", options={"maxiter": 400})
        X = res.x.reshape(-1, 2)
    return X


def snap_octilinear(X, iters=70, dmin=0.7, verbose=False):
    """make every edge exactly octilinear: fix each edge's direction to the nearest of the 8, then find the positions closest to the current ones
    that satisfy all those directions (a sparse linear least-squares) with rising stiffness; a small repulsion between rounds keeps stations apart"""
    import scipy.sparse as sp
    import scipy.sparse.linalg as spl
    n = len(X)
    a = np.array([e[0] for e in E])
    b = np.array([e[1] for e in E])
    m = len(E)
    X = X.copy()
    I2 = sp.identity(2 * n, format="csc")
    for it in range(iters):
        v = X[b] - X[a]
        th = np.arctan2(v[:, 1], v[:, 0])
        k = np.round(th / (math.pi / 4)).astype(int)
        phi = k * math.pi / 4
        nrm = np.stack([-np.sin(phi), np.cos(phi)], 1)
        rows = np.repeat(np.arange(m), 4)
        cols = np.stack([2 * b, 2 * b + 1, 2 * a, 2 * a + 1], 1).ravel()
        vals = np.stack([nrm[:, 0], nrm[:, 1], -nrm[:, 0], -nrm[:, 1]], 1).ravel()
        A = sp.csr_matrix((vals, (rows, cols)), shape=(m, 2 * n))
        lam = min(8.0 * 1.18 ** it, 1e6)
        M = (I2 + lam * (A.T @ A)).tocsc()
        X = spl.spsolve(M, X.ravel()).reshape(-1, 2)
        D = X[:, None, :] - X[None, :, :]
        dist = np.sqrt((D ** 2).sum(2)) + 1e-9
        np.fill_diagonal(dist, 1e9)
        viol = np.clip(dmin - dist, 0, None)
        X = X + ((viol / dist)[:, :, None] * D).sum(1) * 0.5
        if verbose and it % 10 == 0:
            print(" snap", it, measure(X, quick=True))
    return X


def octilinear(dx, dy):
    return dx == 0 or dy == 0 or abs(dx) == abs(dy)


def grid_refine(Xopt, g=0.4, sweeps=60, seed=1, verbose=True, G0=None, movable=None):
    """stations on an integer grid; simulated annealing over 24 candidate moves per station.
    cost = non-octilinear edges + crossings + edge-length drift + drift from the optimised layout + stations too close + sharp turns along a line"""
    rng = np.random.default_rng(seed)
    T = Xopt / g
    G = np.round(T).astype(int)
    if G0 is not None:
        G = np.array(G0, dtype=int)             # (incremental layout: the stations already on the diagram stay where they are, only `movable` ones are placed)
        T = G.astype(float)
    n = len(G)
    a_idx = np.array([e[0] for e in E])
    b_idx = np.array([e[1] for e in E])
    inc = [[] for _ in range(n)]
    for k, (a, b) in enumerate(E):
        inc[a].append(k)
        inc[b].append(k)
    tl = np.linalg.norm(T[b_idx] - T[a_idx], axis=1)
    # consecutive-edge triples along lines (for turn penalties)
    trip = set()
    for lid, st in SEQS:
        for u, v, w in zip(st, st[1:], st[2:]):
            trip.add((ix[u], ix[v], ix[w]))
    trip = list(trip)
    trip_at = [[] for _ in range(n)]
    for t in trip:
        for q in t:
            trip_at[q].append(t)
    w_bend, w_cross, w_len, w_att, w_close, w_turn = 1.0, 4.0, 0.18, 0.10, 3.0, 0.35

    def ang_class(dx, dy):
        return round(math.atan2(dy, dx) / (math.pi / 4)) % 8

    def cross_count(pos, i, edges_i):
        c = 0
        for k in edges_i:
            u, v = E[k]
            pu = pos[u]
            pv = pos[v]
            # vectorised against all edges not sharing an endpoint
            A = pos[a_idx]
            B = pos[b_idx]
            share = (a_idx == u) | (a_idx == v) | (b_idx == u) | (b_idx == v)
            d1 = (B[:, 1] - A[:, 1]) * (pu[0] - A[:, 0]) - (B[:, 0] - A[:, 0]) * (pu[1] - A[:, 1])
            d2 = (B[:, 1] - A[:, 1]) * (pv[0] - A[:, 0]) - (B[:, 0] - A[:, 0]) * (pv[1] - A[:, 1])
            d3 = (pv[1] - pu[1]) * (A[:, 0] - pu[0]) - (pv[0] - pu[0]) * (A[:, 1] - pu[1])
            d4 = (pv[1] - pu[1]) * (B[:, 0] - pu[0]) - (pv[0] - pu[0]) * (B[:, 1] - pu[1])
            hit = (d1 * d2 < 0) & (d3 * d4 < 0) & ~share
            c += int(hit.sum())
        return c

    def node_cost(pos, i):
        c = 0.0
        for k in inc[i]:
            u, v = E[k]
            dx, dy = pos[v] - pos[u]
            L = math.hypot(dx, dy)
            if not octilinear(dx, dy):
                c += w_bend
            if L < 0.9:
                c += 20.0
            c += w_len * abs(L - tl[k])
        c += w_att * float(((pos[i] - T[i]) ** 2).sum())
        # stations too close
        d = np.hypot(*(pos - pos[i]).T)
        d[i] = 99
        c += w_close * float((d < 1.05).sum()) * 4.0
        for (p, q, r) in trip_at[i]:
            v1 = pos[q] - pos[p]
            v2 = pos[r] - pos[q]
            if v1.any() and v2.any():
                turn = abs(((ang_class(v2[0], v2[1]) - ang_class(v1[0], v1[1]) + 4) % 8) - 4)
                c += w_turn * (turn if turn > 1 else 0.0) * 1.0
        c += w_cross * cross_count(pos, i, inc[i])
        return c

    cand = [(dx, dy) for dx in range(-2, 3) for dy in range(-2, 3) if (dx or dy)]
    for sw in range(sweeps):
        temp = 0.7 * (1 - sw / sweeps) ** 2 + 0.01
        moved = 0
        for i in rng.permutation(n if movable is None else np.nonzero(movable)[0]):
            cur = node_cost(G, i)
            best = None
            for (dx, dy) in cand:
                old = G[i].copy()
                G[i] = old + (dx, dy)
                c2 = node_cost(G, i)
                G[i] = old
                dlt = c2 - cur
                if dlt < 0 or rng.random() < math.exp(-dlt / temp):
                    if best is None or c2 < best[0]:
                        best = (c2, (dx, dy))
            if best is not None and best[0] < cur + temp * 0.5:
                G[i] = G[i] + best[1]
                moved += 1
        if verbose and (sw % 5 == 0 or sw == sweeps - 1):
            nb = sum(1 for (a, b) in E if not octilinear(*(G[b] - G[a])))
            print("  sweep %d temp %.2f moved %d non-octilinear edges %d" % (sw, temp, moved, nb))
    return G


def measure(X, quick=False):
    a = np.array([e[0] for e in E])
    b = np.array([e[1] for e in E])
    v = X[b] - X[a]
    th = np.arctan2(v[:, 1], v[:, 0])
    dev = np.abs(((th + math.pi / 8) % (math.pi / 4)) - math.pi / 8)
    D = X[:, None, :] - X[None, :, :]
    dist = np.sqrt((D ** 2).sum(2))
    np.fill_diagonal(dist, 1e9)
    close = int((dist < 0.5).sum() // 2)
    cross = 0
    for i in range(0 if quick else len(E)):
        for j in range(i + 1, len(E)):
            if len({E[i][0], E[i][1], E[j][0], E[j][1]}) < 4:
                continue
            if _seg_cross(X[E[i][0]], X[E[i][1]], X[E[j][0]], X[E[j][1]]):
                cross += 1
    return {"max_dev_deg": float(np.degrees(dev.max())), "n_dev_gt1deg": int((np.degrees(dev) > 1).sum()), "close_pairs": close, "crossings": cross, "min_len": float(np.linalg.norm(v, axis=1).min()), "max_len": float(np.linalg.norm(v, axis=1).max())}


def _seg_cross(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    d1 = ccw(p3, p4, p1)
    d2 = ccw(p3, p4, p2)
    d3 = ccw(p1, p2, p3)
    d4 = ccw(p1, p2, p4)
    return (d1 * d2 < -1e-9) and (d3 * d4 < -1e-9)


THAMES = [[51.4613, -0.3037], [51.4740, -0.3010], [51.4870, -0.2900], [51.4830, -0.2650], [51.4870, -0.2350], [51.4800, -0.2200], [51.4667, -0.2150], [51.4640, -0.1900],
          [51.4790, -0.1780], [51.4830, -0.1560], [51.4880, -0.1320], [51.4980, -0.1230], [51.5060, -0.1215], [51.5090, -0.1150], [51.5110, -0.1040], [51.5085, -0.0880], [51.5060, -0.0740],
          [51.5040, -0.0530], [51.5020, -0.0330], [51.4980, -0.0170], [51.4920, -0.0090], [51.4830, -0.0100], [51.4850, 0.0050], [51.4960, 0.0150], [51.5040, 0.0300], [51.5030, 0.0500], [51.4960, 0.0700]]


def sgn(v):
    return (v > 0) - (v < 0)


def dogleg_options(pa, pb):
    """the two ways of joining two grid points with one horizontal/vertical/diagonal run and one diagonal/axis run"""
    dx, dy = int(pb[0] - pa[0]), int(pb[1] - pa[1])
    if octilinear(dx, dy):
        return [[list(pa), list(pb)]]
    ax, ay = abs(dx), abs(dy)
    sx, sy = sgn(dx), sgn(dy)
    if ax >= ay:
        # axis run of (ax - ay) in x plus a diagonal of ay
        c1 = [pa[0] + sx * (ax - ay), pa[1]]            # axis first, then diagonal
        c2 = [pa[0] + sx * ay, pa[1] + sy * ay]         # diagonal first, then axis
    else:
        c1 = [pa[0], pa[1] + sy * (ay - ax)]
        c2 = [pa[0] + sx * ax, pa[1] + sy * ax]
    return [[list(pa), [int(c1[0]), int(c1[1])], list(pb)], [list(pa), [int(c2[0]), int(c2[1])], list(pb)]]


def seg_point_dist(p, a, b):
    ab = np.array(b, float) - np.array(a, float)
    t = np.clip(np.dot(np.array(p, float) - a, ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
    return float(np.linalg.norm(np.array(p, float) - (np.array(a, float) + t * ab)))


def route_edges(G):
    """one polyline per edge; where an edge is not octilinear pick the dogleg that keeps clear of stations and continues the neighbouring edges"""
    n = len(G)
    paths = []
    for k, (a, b) in enumerate(E):
        opts = dogleg_options(G[a], G[b])
        if len(opts) == 1:
            paths.append(opts[0])
            continue
        best = None
        for o in opts:
            c = 0.0
            for i in range(n):
                if i in (a, b):
                    continue
                for q in range(len(o) - 1):
                    d = seg_point_dist(G[i], o[q], o[q + 1])
                    if d < 0.8:
                        c += 5.0 * (0.8 - d)
            # continuing straight at the endpoints
            for (end, other) in ((a, 0), (b, 1)):
                seg = (o[0], o[1]) if other == 0 else (o[-1], o[-2])
                vd = np.array(seg[1], float) - np.array(seg[0], float)
                for k2 in range(len(E)):
                    if k2 == k or end not in E[k2]:
                        continue
                    if not set(E_LINES[k2]) & set(E_LINES[k]):
                        continue
                    v2 = G[E[k2][1]] - G[E[k2][0]] if E[k2][0] == end else G[E[k2][0]] - G[E[k2][1]]
                    if np.linalg.norm(vd) > 0 and np.linalg.norm(v2) > 0:
                        cs = float(np.dot(vd, v2) / (np.linalg.norm(vd) * np.linalg.norm(v2)))
                        c += 0.4 * (1 + cs)             # a turn at the station costs, straight through does not
            if best is None or c < best[0]:
                best = (c, o)
        paths.append(best[1])
    return paths


def station_dirs(G, paths):
    """unit direction of the line through each station (for the tick mark), from the first path segment of each incident edge"""
    dirs = [None] * len(G)
    acc = [[] for _ in G]
    for k, (a, b) in enumerate(E):
        pa = paths[k]
        va = np.array(pa[1], float) - np.array(pa[0], float)
        vb = np.array(pa[-2], float) - np.array(pa[-1], float)
        acc[a].append(va / (np.linalg.norm(va) + 1e-9))
        acc[b].append(vb / (np.linalg.norm(vb) + 1e-9))
    for i, vs in enumerate(acc):
        if not vs:
            dirs[i] = [1.0, 0.0]
            continue
        # align all to the first (opposite directions along a line) and average
        v0 = vs[0]
        m = np.zeros(2)
        for v in vs:
            m += v if np.dot(v, v0) >= 0 else -v
        nm = np.linalg.norm(m)
        dirs[i] = [float(m[0] / nm), float(m[1] / nm)] if nm > 1e-6 else [float(v0[0]), float(v0[1])]
    return dirs


def label_stations(G, paths):
    """8 candidate positions (0=E 1=NE 2=N 3=NW 4=W 5=SW 6=S 7=SE) per station; greedy + local improvement against lines, stations and other labels"""
    n = len(G)
    CW, CH = 0.27, 0.55          # label size in grid cells per character / line height (game font at a zoom where every name is shown)
    rm = 0.62
    segs = []
    seg_n = []
    bundle = [1] * n
    for k, pth in enumerate(paths):
        nl = len(E_LINES[k])
        for q in range(len(pth) - 1):
            segs.append((pth[q], pth[q + 1]))
            seg_n.append(nl)
        bundle[E[k][0]] = max(bundle[E[k][0]], nl)
        bundle[E[k][1]] = max(bundle[E[k][1]], nl)
    segs_a = np.array([[s[0][0], s[0][1], s[1][0], s[1][1]] for s in segs], float)
    seg_pad = 0.10 + 0.17 * (np.array(seg_n, float) - 1.0) * 0.5 + 0.17 * 0.5      # half the bundle width (line width 0.34 cells) plus a little air
    names = [S[k]["name"] for k in ids]
    inter = [len(S[k]["lines"]) > 1 for k in ids]
    pref = [0.0, 0.5, 0.9, 0.5, 0.15, 0.5, 0.9, 0.5]
    dirs8 = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)]

    def box(i, d):
        w = len(names[i]) * CW
        px, py = float(G[i][0]), float(G[i][1])
        dx, dy = dirs8[d]
        rm = 0.62 + 0.17 * (bundle[i] - 1)          # clear of the interchange capsule across the bundle
        if d == 0:
            return (px + rm, py - CH / 2, px + rm + w, py + CH / 2)
        if d == 4:
            return (px - rm - w, py - CH / 2, px - rm, py + CH / 2)
        if d == 2:
            return (px - w / 2, py - rm - CH, px + w / 2, py - rm)
        if d == 6:
            return (px - w / 2, py + rm, px + w / 2, py + rm + CH)
        if d == 1:
            return (px + rm * 0.6, py - rm * 0.6 - CH, px + rm * 0.6 + w, py - rm * 0.6)
        if d == 3:
            return (px - rm * 0.6 - w, py - rm * 0.6 - CH, px - rm * 0.6, py - rm * 0.6)
        if d == 5:
            return (px - rm * 0.6 - w, py + rm * 0.6, px - rm * 0.6, py + rm * 0.6 + CH)
        return (px + rm * 0.6, py + rm * 0.6, px + rm * 0.6 + w, py + rm * 0.6 + CH)

    def seg_hits_box(bx, own=()):
        ax, ay, cx, cy = segs_a[:, 0], segs_a[:, 1], segs_a[:, 2], segs_a[:, 3]
        # sample points along each segment (segments are short): any sample inside the (bundle-padded) box counts
        hit = np.zeros(len(segs_a), bool)
        for t in np.linspace(0, 1, 13):
            x = ax + (cx - ax) * t
            y = ay + (cy - ay) * t
            hit |= (x > bx[0] - seg_pad) & (x < bx[2] + seg_pad) & (y > bx[1] - seg_pad) & (y < bx[3] + seg_pad)
        return int(hit.sum())

    def rects_overlap(r1, r2, pad=0.08):
        return not (r1[2] + pad < r2[0] or r2[2] + pad < r1[0] or r1[3] + pad < r2[1] or r2[3] + pad < r1[1])

    chosen = [0] * n
    boxes = [None] * n
    order = sorted(range(n), key=lambda i: (not inter[i], -len(S[ids[i]]["lines"])))

    def cost(i, d):
        bx = box(i, d)
        c = pref[d]
        c += 3.5 * seg_hits_box(bx)
        for j in range(n):
            if j == i:
                continue
            # other station markers
            if bx[0] - 0.2 < G[j][0] < bx[2] + 0.2 and bx[1] - 0.2 < G[j][1] < bx[3] + 0.2:
                c += 6.0
            if boxes[j] is not None and rects_overlap(bx, boxes[j]):
                c += 5.0
        return c

    for i in order:
        cs = [cost(i, d) for d in range(8)]
        chosen[i] = int(np.argmin(cs))
        boxes[i] = box(i, chosen[i])
    for _ in range(4):
        for i in order:
            boxes[i] = None
            cs = [cost(i, d) for d in range(8)]
            chosen[i] = int(np.argmin(cs))
            boxes[i] = box(i, chosen[i])
    bad = sum(1 for i in range(n) if cost(i, chosen[i]) > 4.0)
    print("labels placed; %d still overlapping something" % bad)
    return chosen


def export(G, P1, sc, c_geo):
    paths = route_edges(G)
    dirs = station_dirs(G, paths)
    lab = label_stations(G, paths)
    # river: warp its points exactly as the stations were (same centre/scale), then displace by the neighbouring stations' displacement
    A = np.array([[S[k]["lat"], S[k]["lon"], 1.0] for k in ids])
    cx = np.linalg.lstsq(A, P_GEO[:, 0], rcond=None)[0]
    cy = np.linalg.lstsq(A, P_GEO[:, 1], rcond=None)[0]
    river_geo = np.array([[np.dot([la, lo, 1.0], cx), np.dot([la, lo, 1.0], cy)] for la, lo in THAMES])
    z1 = np.array([i for i, k in enumerate(ids) if S[k]["zone"] == 1])
    cz = np.median(P_GEO[z1], axis=0)
    v = river_geo - cz
    r = np.linalg.norm(v, axis=1) + 1e-9
    rw = cz + v * (r ** 0.62 / r)[:, None]
    river1 = (rw - cz) * sc
    disp = G - P1 / 0.4 * 0.0 - (P1 / 0.4)          # displacement in grid cells (final cells minus warped-geographic cells)
    river_cells = river1 / 0.4
    out_river = []
    for q in river_cells:
        d = np.linalg.norm((P1 / 0.4) - q, axis=1)
        nn = np.argsort(d)[:4]
        w = 1.0 / (d[nn] + 0.6)
        dd = (disp[nn] * w[:, None]).sum(0) / w.sum()
        out_river.append(q + dd)
    river = [[round(float(p[0]), 2), round(-float(p[1]), 2)] for p in out_river]
    data = {
        "cell": 0.4,
        "stations": {ids[i]: {"p": [int(G[i][0]), int(-G[i][1])], "d": [round(dirs[i][0], 3), round(-dirs[i][1], 3)], "l": int(lab[i])} for i in range(len(ids))},
        "edges": [{"a": ids[a], "b": ids[b], "lines": E_LINES[k], "pts": [[int(p[0]), int(-p[1])] for p in paths[k]]} for k, (a, b) in enumerate(E)],
        "links": [{"a": ids[a], "b": ids[b]} for a, b in LINKS],
        "thames": river,
    }
    # label directions were computed with y up; the game draws y down, so mirror the vertical component of the 8 directions
    flip = {0: 0, 1: 7, 2: 6, 3: 5, 4: 4, 5: 3, 6: 2, 7: 1}
    for k, st in data["stations"].items():
        st["l"] = flip[st["l"]]
    path = os.path.join(ROOT, "data", "tube_diagram.json")
    json.dump(data, open(path, "w"), separators=(",", ":"))
    print("wrote", path, os.path.getsize(path), "bytes")


def add_stations():
    """Incremental layout: keep every station that is already on data/tube_diagram.json where it is and place only the new ones (the Elizabeth line's own stations) on the grid,
    starting from their warped geographic position moved with the displacement of the nearest old stations. The scale is the old one (median edge length of the old lines' edges)."""
    old = json.load(open(os.path.join(ROOT, "data", "tube_diagram.json")))
    G = np.zeros((N, 2))
    known = np.zeros(N, dtype=bool)
    for k, st in old["stations"].items():
        if k in ix:
            G[ix[k]] = (st["p"][0], -st["p"][1])
            known[ix[k]] = True
    P1, c = warp(P_GEO)
    old_edges = [(a, b) for (a, b), lns in zip(E, E_LINES) if lns != ["elizabeth"]]
    sc = 1.0 / np.median([np.linalg.norm(P1[b] - P1[a]) for a, b in old_edges])
    P1 = (P1 - c) * sc
    disp = G[known] - P1[known] / 0.4
    base = P1[known] / 0.4
    for i in np.nonzero(~known)[0]:
        q = P1[i] / 0.4
        d = np.linalg.norm(base - q, axis=1)
        nn = np.argsort(d)[:4]
        w = 1.0 / (d[nn] + 0.6)
        G[i] = np.round(q + (disp[nn] * w[:, None]).sum(0) / w.sum())
    print("placing %d new stations next to %d old ones" % ((~known).sum(), known.sum()))
    G = grid_refine(G * 0.4, sweeps=90, G0=G, movable=~known)
    X = G * 0.4
    print("grid:     ", measure(X))
    np.save(os.path.join(ROOT, "build", "diagram", "G.npy"), G)
    np.save(os.path.join(ROOT, "build", "diagram", "X.npy"), X)
    export(G, P1, sc, c)
    if "--png" in sys.argv:
        render_png(X, os.path.join(ROOT, "build", "diagram", "layout.png"))


def main():
    if "--add" in sys.argv:
        return add_stations()
    P1, c = warp(P_GEO)
    # scale so the median edge length is about 1 unit
    lens = np.array([np.linalg.norm(P1[b] - P1[a]) for a, b in E])
    sc = 1.0 / np.median(lens)
    P1 = (P1 - c) * sc
    stages = []
    for wa in [0.02, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 4.0]:
        stages.append({"ang": wa, "len": 0.6, "anchor": 0.04, "rep": 4.0, "dmin": 0.75, "lmin": 0.8, "lmax": 4.5})
    X = optimise(P1, stages)
    print("optimised:", measure(X))
    if os.path.exists(os.path.join(ROOT, "build", "diagram", "G.npy")) and "--relayout" not in sys.argv:
        G = np.load(os.path.join(ROOT, "build", "diagram", "G.npy"))
        print("using saved grid layout (pass --relayout to recompute)")
    else:
        G = grid_refine(X)
        np.save(os.path.join(ROOT, "build", "diagram", "G.npy"), G)
    X = G * 0.4
    print("grid:     ", measure(X))
    np.save(os.path.join(ROOT, "build", "diagram", "X.npy"), X)
    export(G, P1, sc, c)
    if "--png" in sys.argv:
        render_png(X, os.path.join(ROOT, "build", "diagram", "layout.png"))


def render_png(X, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(24, 18), dpi=80)
    for (a, b), lns in zip(E, E_LINES):
        for k, lid in enumerate(lns):
            ax.plot([X[a][0], X[b][0]], [X[a][1], X[b][1]], color=LINES[lid]["color"], lw=3, solid_capstyle="round", zorder=2)
    for i, k in enumerate(ids):
        inter = len(S[k]["lines"]) > 1
        ax.scatter([X[i][0]], [X[i][1]], s=40 if inter else 12, c="white", edgecolors="black", zorder=3)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.savefig(path, bbox_inches="tight")


if __name__ == "__main__":
    main()
