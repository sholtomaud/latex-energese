#!/usr/bin/env python3
"""Measure Odum's published symbols to produce the targets in invariants.json.

The reference sheet draws each symbol with its inflow, outflow and heat-sink
arrows attached, so a bounding box around the ink measures the arrows too. This
isolates the symbol itself by flood-filling its interior from a seed point:
the outline is closed, the arrows are outside it, so the filled region is the
body alone.

Run it to regenerate the numbers rather than editing invariants.json by hand:

    python3 tests/fidelity/measure_reference.py

The seed points below were chosen by eye from the sheet and are the only manual
input; everything downstream is measured. A seed that lands on ink, or inside a
shape whose outline is broken at this resolution, is reported rather than
silently producing a wrong number.
"""

import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SHEET = os.path.join(ROOT, "reference-images", "complete-odum-symbols.png")

# (x, y) inside each symbol's closed outline on the reference sheet.
SEEDS = {
    "source":      (84, 50),
    "storage":     (88, 140),
    "interaction": (90, 320),
    "transaction": (88, 424),
    "producer":    (90, 927),
    "consumer":    (92, 1050),
    "gain":        (80, 525),
    "loop_limited":(85, 632),
    "switch":      (100, 1325),
}

FILL = 128
MAX_REASONABLE = (300, 400)


def measure(sheet, seed):
    work = sheet.copy()
    if work.getpixel(seed) < 128:
        return None, "seed lands on ink"
    ImageDraw.floodfill(work, seed, FILL, thresh=10)
    px = work.load()
    xs, ys = [], []
    for y in range(work.height):
        for x in range(work.width):
            if px[x, y] == FILL:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None, "nothing filled"
    w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
    if w > MAX_REASONABLE[0] or h > MAX_REASONABLE[1]:
        return None, "fill escaped (%dx%d): outline not closed at this resolution" % (w, h)
    return {"width": w, "height": h, "aspect": round(w / h, 3)}, None


def main():
    if not os.path.exists(SHEET):
        print("reference sheet not found: %s" % SHEET)
        return 1
    grey = Image.open(SHEET).convert("L")
    sheet = grey.point(lambda p: 0 if p < 128 else 255).convert("L")

    print("Measured from %s\n" % os.path.relpath(SHEET, ROOT))
    print("  %-13s %-10s %-10s %s" % ("symbol", "w x h px", "aspect", ""))
    results, failed = {}, 0
    for name, seed in sorted(SEEDS.items()):
        got, err = measure(sheet, seed)
        if err:
            print("  %-13s %s" % (name, err))
            failed += 1
            continue
        results[name] = got
        print("  %-13s %-10s %-10.3f" % (name, "%d x %d" % (got["width"], got["height"]),
                                         got["aspect"]))

    inv_path = os.path.join(HERE, "invariants.json")
    if os.path.exists(inv_path):
        with open(inv_path) as fh:
            recorded = json.load(fh)["symbols"]
        print("\nAgainst the recorded targets:")
        for name, got in sorted(results.items()):
            if name not in recorded:
                print("  %-13s measured %.3f, not recorded" % (name, got["aspect"]))
                continue
            want = recorded[name]["aspect"]
            delta = got["aspect"] - want
            flag = "" if abs(delta) < 0.001 else "   <-- differs from invariants.json"
            print("  %-13s measured %.3f, recorded %.3f%s" % (name, got["aspect"], want, flag))

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
