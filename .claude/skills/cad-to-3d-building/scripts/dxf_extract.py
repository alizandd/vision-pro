#!/usr/bin/env python3
"""Extract building linework from an AutoCAD DXF and isolate one elevation/plan view.

Blender 5.x ships no DXF importer, and a real architectural sheet holds many views,
dimensions, text and hatching. This pure-Python parser (no deps) pulls only the
building-layer LINE/LWPOLYLINE segments, clusters the sheet into separate drawings,
picks the one that looks like a building, and writes origin-shifted metre-scale
segments as JSON for Blender to rebuild as a backdrop.

Usage:
    python3 dxf_extract.py INPUT.dxf OUTPUT.json [--units inch|mm|m] [--minh 7] [--maxh 16]

Header hints (read automatically if --units omitted): $INSUNITS 1=inch 4=mm 6=m;
$LUNITS 4=architectural(inch); $MEASUREMENT 0=imperial 1=metric.
"""
import json, sys, argparse
from collections import defaultdict, deque

UNIT_TO_M = {"inch": 0.0254, "mm": 0.001, "m": 1.0}
# building layers we keep; drop DIM/TEXT/HATCH/GRID/DEFPOINTS etc.
KEEP_LAYERS = {"BLDG", "FOOTING", "A-DOORS", "A-WINDOWS", "WINDOW", "WINDOWS",
               "ROOF", "WALL", "A-WALL", "A-ROOF"}


def read_pairs(path):
    with open(path, "r", errors="replace") as f:
        lines = f.read().splitlines()
    it = iter(lines)
    out = []
    for code in it:
        try:
            val = next(it)
        except StopIteration:
            break
        out.append((code.strip(), val.strip()))
    return out


def guess_units(pairs):
    def val_after(name):
        for i in range(len(pairs) - 2):
            if pairs[i][1] == name:
                return pairs[i + 2][1]
        return None
    insunits = val_after("$INSUNITS")
    if insunits == "1":
        return "inch"
    if insunits == "4":
        return "mm"
    if insunits == "6":
        return "m"
    if val_after("$LUNITS") == "4":
        return "inch"  # architectural display ⇒ inches
    return "inch"


def extract_segments(pairs):
    """Return list of (layer, x1, y1, x2, y2) in drawing units."""
    n = len(pairs)
    start = -1
    for k in range(n - 1):
        if pairs[k] == ("0", "SECTION") and pairs[k + 1] == ("2", "ENTITIES"):
            start = k
            break
    if start < 0:
        return []
    segs = []
    i = start + 2
    while i < n:
        code, val = pairs[i]
        if code == "0":
            if val == "ENDSEC":
                break
            typ = val
            i += 1
            lay = "0"
            recs = []
            while i < n and pairs[i][0] != "0":
                c, v = pairs[i]
                if c == "8":
                    lay = v
                elif c in ("10", "20", "11", "21"):
                    recs.append((c, float(v)))
                i += 1
            if typ == "LINE":
                d = {c: v for c, v in recs}
                if all(k in d for k in ("10", "20", "11", "21")):
                    segs.append((lay, d["10"], d["20"], d["11"], d["21"]))
            elif typ in ("LWPOLYLINE", "POLYLINE"):
                pts, curx = [], None
                for c, v in recs:
                    if c == "10":
                        curx = v
                    elif c == "20" and curx is not None:
                        pts.append((curx, v)); curx = None
                for a, b in zip(pts, pts[1:]):
                    segs.append((lay, a[0], a[1], b[0], b[1]))
            continue
        i += 1
    return segs


def cluster_and_pick(segs, scale, minh=7.0, maxh=16.0, minw=4.0, maxw=45.0):
    """Flood-fill cluster on a 1 m grid; return the densest building-shaped cluster."""
    bldg = [s for s in segs if s[0] in KEEP_LAYERS] or segs
    cells = defaultdict(list)
    occ = set()

    def cell(x, y):
        return (int(round(x * scale)), int(round(y * scale)))

    for idx, (lay, x1, y1, x2, y2) in enumerate(bldg):
        for (x, y) in ((x1, y1), (x2, y2), ((x1 + x2) / 2, (y1 + y2) / 2)):
            c = cell(x, y); occ.add(c); cells[c].append(idx)

    seen, comps = set(), []
    for c in occ:
        if c in seen:
            continue
        q = deque([c]); seen.add(c); comp = []
        while q:
            cc = q.popleft(); comp.append(cc)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nc = (cc[0] + dx, cc[1] + dy)
                    if nc in occ and nc not in seen:
                        seen.add(nc); q.append(nc)
        comps.append(comp)

    cands = []
    for comp in comps:
        idxs = set()
        for cc in comp:
            idxs.update(cells[cc])
        xs, ys = [], []
        for j in idxs:
            _, x1, y1, x2, y2 = bldg[j]
            xs += [x1 * scale, x2 * scale]; ys += [y1 * scale, y2 * scale]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if minh <= h <= maxh and minw <= w <= maxw:
            cands.append((len(idxs), w, h, min(xs), min(ys), idxs))
    if not cands:
        return None
    cands.sort(key=lambda t: -t[0])
    return cands[0], bldg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dxf"); ap.add_argument("out")
    ap.add_argument("--units", choices=list(UNIT_TO_M))
    ap.add_argument("--minh", type=float, default=7.0)
    ap.add_argument("--maxh", type=float, default=16.0)
    args = ap.parse_args()

    pairs = read_pairs(args.dxf)
    units = args.units or guess_units(pairs)
    scale = UNIT_TO_M[units]
    segs = extract_segments(pairs)
    picked = cluster_and_pick(segs, scale, args.minh, args.maxh)
    if not picked:
        print("No building-shaped cluster found; widen --minh/--maxh.", file=sys.stderr)
        sys.exit(1)
    (count, w, h, ox, oy, idxs), bldg = picked
    out = []
    for j in idxs:
        _, x1, y1, x2, y2 = bldg[j]
        out.append([round(x1 * scale - ox, 4), round(y1 * scale - oy, 4),
                    round(x2 * scale - ox, 4), round(y2 * scale - oy, 4)])
    json.dump({"units": units, "scale_to_m": scale, "w": round(w, 3),
               "h": round(h, 3), "segments": out}, open(args.out, "w"))
    print(f"units={units} scale={scale}  picked view {w:.2f}m x {h:.2f}m  "
          f"{len(out)} segments -> {args.out}")


if __name__ == "__main__":
    main()
