#!/usr/bin/env python3
"""Fidelity harness for energese. See AGENTS.md section 2 for the methodology.

Two tiers, because only one of them can honestly be pixel-exact:

  regression   Tier 1. Compares a render against our own approved golden,
               byte for byte. Rendering is deterministic, so any difference is
               a real change; a diff panel is written for every failure.

  conformance  Tier 2. Compares a render against geometry measured from
               Odum's published symbols. Those references are 144 DPI captures,
               so this asserts scale-independent invariants within recorded
               tolerances -- never pixels.

Subcommands:
    render       build every fixture to out/
    regression   compare out/ against golden/, writing diffs on failure
    accept       promote out/ to golden/ (do this only after reviewing diffs)
    conformance  check rendered symbols against invariants.json
    fonts        assert the expected fonts are embedded (guards golden validity)
    sheet        build a contact sheet of every symbol for human review
    compare      build side-by-side reference/render figures (used by the paper)
    overlay      overlay a whole diagram on its published original
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import esmeasure  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "out")
GOLDEN = os.path.join(HERE, "golden")
DIFF = os.path.join(HERE, "diff")
INVARIANTS = os.path.join(HERE, "invariants.json")

# Rasterisation is part of a golden's identity. Changing this invalidates all
# of them, so it is a constant rather than an option.
DPI = 300

# Symbols rendered in isolation, and again with their ports marked. A symbol
# test that draws only the outline will not catch a port that has drifted off
# the edge, so the port fixtures mark every one -- and a port off the outline
# is a pathway attached to nothing.
SYMBOLS = {
    "source":      {"label": "Source"},
    "storage":     {"label": "Storage"},
    "producer":    {"label": "Producer"},
    "consumer":    {"label": "Consumer"},
    "transaction": {"label": "Transaction"},
    "interaction": {"label": "Interaction"},
    "gain":        {"label": "G"},
    "loop_limited":{"label": "Loop"},
    "switch":      {"label": "Switch"},
}

# A golden is only comparable across machines if the same fonts were used.
# energese.sty guards \setsansfont with \IfFontExistsTF and falls back
# silently, which is right for a user whose install lacks tex-gyre and fatal
# for regression: the same source would render differently in two places.
REQUIRED_FONTS = ["TeXGyreHerosCondensed"]

# Whole diagrams, rendered from the examples that ship with the package.
DIAGRAMS = ["source-store", "simple_system", "aggregated-economy",
            "source-store-native", "simple_system-native",
            "aggregated-economy-native"]

# Diagrams built for the harness rather than shipped as examples, each
# exercising something the examples do not.
FIXTURES = {
    # The auto-fitted system window, which no shipped example exercises: they
    # either have no frame or give its corners explicitly. What the golden
    # records is that the frame sits a fixed margin outside the *extents* of
    # what is inside it -- and that the source stays outside, as Odum draws it.
    "diagram-auto-boundary": r"""
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\begin{energese}
    \esmeta{column_spacing=3.0, row_spacing=1.6, system_boundary,
            heat_sink_label={losses}}
    \esnode{sun}{source}     {Tr=1,    label={Sun}}
    \esnode{farm}{producer}  {Tr=10,   label={Environmental\\Systems}}
    \esnode{store}{storage}  {Tr=100,  label={Q}}
    \esnode{town}{consumer}  {Tr=2000, label={Town}}
    \esflow{sun}{farm}{energy}
    \esflow{farm}{store}{energy}
    \esflow{store}{town}{energy}
\end{energese}
\end{document}
""".lstrip(),
    # Obstacle routing, which no shipped example exercises either: their
    # pathways run between neighbours and meet nothing. Here a pathway is
    # declared from the source straight to the consumer, across a middle column
    # holding two symbols it must go around -- the case the old step-over
    # router cleared into a second obstacle. The golden records the way round.
    "diagram-obstacle-routing": r"""
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\begin{energese}
    \esmeta{column_spacing=3.2, row_spacing=1.5, show_heat_sink=false}

    \esnode{sun}{source}      {Tr=1,    label={Sun}}
    \esnode{plant}{producer}  {Tr=10,   label={Plant}}
    \esnode{stack}{storage}   {Tr=10,   label={Q}, layer_hint=control}
    \esnode{store}{storage}   {Tr=100,  label={Store}}
    \esnode{town}{consumer}   {Tr=2000, label={Town}}

    \esflow{sun}{plant}{energy}
    \esflow{plant}{store}{energy}
    \esflow{store}{town}{energy}
    \esflow{sun}{town}{energy}
\end{energese}
\end{document}
""".lstrip(),
    # A GSSK model, read straight from the simulation kernel's own format --
    # the output of gssk-dia, not a hand-written example. What the golden
    # records is the whole normalisation: the sink node collapsed into
    # energese's own dissipation handling, the canvas coordinates converted out
    # of pixels and flipped the right way up, transformity derived from the
    # chain, and `visual.label` lifted onto the symbol.
    "diagram-gssk": r"""
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\renderEnergese{tests/fixtures/gssk-grass.json}
\end{document}
""".lstrip(),
    # A diagram drawn under a TikZ `scale`, which every other fixture and every
    # shipped example happens not to be -- and which nothing here caught when
    # the port count was published as a coordinate offset and came back scaled.
    # The allocator then quantised onto a ring of ten points that the shape had
    # drawn as twelve, and dissipation left the corner of a symbol instead of
    # its underside. The paper's own figures are drawn at 0.85.
    "diagram-scaled": r"""
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\begin{energese}[scale=0.85]
    \esmeta{column_spacing=3.2, row_spacing=1.6}
    \esnode{sun}{source}     {Tr=1,    label={Sun}}
    \esnode{grass}{producer} {Tr=100,  label={Grass}}
    \esnode{cow}{consumer}   {Tr=2000, label={Cow}}
    \esflow{sun}{grass}{energy}
    \esflow{grass}{cow}{energy}
\end{energese}
\end{document}
""".lstrip(),
    # Port contention, which no shipped example exercises hard enough to be a
    # test. Four pathways converge on one consumer and three leave it, all of
    # them asking for the two anchors on its horizontal axis; a symbol that let
    # them share would draw seven pathways as two. The golden records where each
    # one attached, so a change in the allocator -- which port it starts from,
    # which way it steps when that one is taken -- shows up as a diff rather
    # than as a diagram that still looks plausible.
    "diagram-port-contention": r"""
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\begin{energese}
    \esmeta{column_spacing=3.5, row_spacing=1.4, show_heat_sink=false}

    \esnode{a}{source}   {Tr=1,    label={A}}
    \esnode{b}{source}   {Tr=1,    label={B}}
    \esnode{c}{source}   {Tr=1,    label={C}}
    \esnode{d}{source}   {Tr=1,    label={D}}
    \esnode{hub}{consumer}{Tr=100, label={Hub}, magnitude=1.4}
    \esnode{x}{storage}  {Tr=1000, label={X}}
    \esnode{y}{storage}  {Tr=1000, label={Y}}
    \esnode{z}{storage}  {Tr=1000, label={Z}}

    \esflow{a}{hub}{energy}
    \esflow{b}{hub}{energy}
    \esflow{c}{hub}{energy}
    \esflow{d}{hub}{energy}
    \esflow{hub}{x}{energy}
    \esflow{hub}{y}{energy}
    \esflow{hub}{z}{energy}
\end{energese}
\end{document}
""".lstrip(),
}


def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def tex_symbol(name, label=None, ports=False):
    """A standalone document holding one symbol.

    `bare` (no label) is what conformance measures: with no text the shape sits
    at its minimum size, which is where Odum's canonical proportions apply.

    The `ports` variant marks every port on the connection ring, and only
    those: a named anchor is quantised to the nearest port before anything
    attaches to it, so the ring is the whole set of places a pathway can meet
    this symbol. Drawing the named anchors as well would show points no
    pathway ever uses. The count comes from the shape's own `ringcount`
    anchor, so the fixture marks the ports the symbol actually has rather than
    a fixed number of them -- a symbol carrying 22 ports drawn with 48 dots
    would hide a wrong count behind the repeats.
    """
    body = [r"\begin{tikzpicture}",
            r"  \node[energese %s] (s) {%s};" % (name, label or "")]
    if ports:
        body += [r"  \pgfpointanchor{s}{center}\pgf@xa=\pgf@x",
                 r"  \pgfpointanchor{s}{ringcount}\advance\pgf@x by-\pgf@xa",
                 r"  \pgfmathtruncatemacro{\portmax}{min(48, round(\the\pgf@x)) - 1}",
                 r"  \foreach \i in {0,...,\portmax}"
                 r" { \fill[red] (s.ring\i) circle (0.9pt); }"]
    body.append(r"\end{tikzpicture}")
    return "\n".join([r"\documentclass{standalone}",
                      r"\usepackage{energese}",
                      r"\makeatletter",
                      r"\begin{document}"] + body + [r"\end{document}", ""])


def render_one(lualatex, pdftoppm, jobname, source):
    path = os.path.join(OUT, jobname + ".tex")
    with open(path, "w") as fh:
        fh.write(source)
    env = dict(os.environ, TEXINPUTS=".:", SOURCE_DATE_EPOCH="0", FORCE_SOURCE_DATE="1")
    res = subprocess.run(
        [lualatex, "--interaction=nonstopmode", "--halt-on-error",
         "-output-directory=" + OUT, path],
        cwd=ROOT, capture_output=True, text=True, stdin=subprocess.DEVNULL, env=env)
    pdf = os.path.join(OUT, jobname + ".pdf")
    if res.returncode != 0 or not os.path.exists(pdf):
        return False, res.stdout[-1500:]
    subprocess.run([pdftoppm, "-png", "-r", str(DPI), "-gray", "-singlefile",
                    pdf, os.path.join(OUT, jobname)], check=True)
    return True, None


def cmd_render(args):
    os.makedirs(OUT, exist_ok=True)
    failures = []
    for name, spec in SYMBOLS.items():
        for jobname, source in (
            ("symbol-%s-bare" % name, tex_symbol(name)),
            ("symbol-%s-ports" % name, tex_symbol(name, spec["label"], ports=True)),
        ):
            ok, err = render_one(args.lualatex, args.pdftoppm, jobname, source)
            print(("  ok   " if ok else "  FAIL ") + jobname)
            if not ok:
                failures.append((jobname, err))
    for diagram in DIAGRAMS:
        src = os.path.join(ROOT, "examples", diagram + ".tex")
        if not os.path.exists(src):
            print("  skip  %s (no such example)" % diagram)
            continue
        ok, err = render_one(args.lualatex, args.pdftoppm, "diagram-" + diagram,
                             open(src).read())
        print(("  ok   " if ok else "  FAIL ") + "diagram-" + diagram)
        if not ok:
            failures.append((diagram, err))
    for jobname, source in sorted(FIXTURES.items()):
        ok, err = render_one(args.lualatex, args.pdftoppm, jobname, source)
        print(("  ok   " if ok else "  FAIL ") + jobname)
        if not ok:
            failures.append((jobname, err))
    for name, err in failures:
        print("\n--- %s ---\n%s" % (name, err))
    return 1 if failures else 0


# Only actual renders are golden-tracked. The contact sheet and the
# side-by-side panels are assembled *from* those renders, so tracking them adds
# no coverage and lets a stale derived image be promoted as if it were output.
RENDER_PREFIXES = ("symbol-", "diagram-")

# Derived review images, never golden-tracked: contact sheet tiles, comparison
# panels and overlays are all assembled from renders that are tracked already.


def rendered():
    if not os.path.isdir(OUT):
        return []
    return sorted(f for f in os.listdir(OUT)
                  if f.endswith(".png") and f.startswith(RENDER_PREFIXES))


def cmd_regression(args):
    os.makedirs(GOLDEN, exist_ok=True)
    shutil.rmtree(DIFF, ignore_errors=True)
    os.makedirs(DIFF, exist_ok=True)
    files = rendered()
    if not files:
        print("no renders found -- run `make regression` which renders first")
        return 1
    changed, missing = [], []
    for name in files:
        gold = os.path.join(GOLDEN, name)
        if not os.path.exists(gold):
            missing.append(name)
            continue
        if esmeasure.exact(os.path.join(OUT, name), gold):
            print("  ok      %s" % name)
        else:
            n = esmeasure.diff_image(os.path.join(OUT, name), gold,
                                     os.path.join(DIFF, name))
            print("  CHANGED %s  (%d px differ, diff written)" % (name, n))
            changed.append(name)
    for name in missing:
        print("  NEW     %s  (no golden yet)" % name)
    if changed or missing:
        print("\n%d changed, %d new. Review tests/fidelity/diff/, then "
              "`make regression-accept` if the change is intended."
              % (len(changed), len(missing)))
        return 1
    print("\nAll %d renders match their goldens." % len(files))
    return 0


def cmd_accept(args):
    os.makedirs(GOLDEN, exist_ok=True)
    n = 0
    for name in rendered():
        shutil.copy2(os.path.join(OUT, name), os.path.join(GOLDEN, name))
        n += 1
    shutil.rmtree(DIFF, ignore_errors=True)
    print("Promoted %d renders to goldens. Commit them with the code change." % n)
    return 0


def reference_solid(name):
    """The reference symbol as a filled region.

    Taken from the flood-fill directly rather than by filling a crop: a crop of
    the sheet still contains the inflow and outflow arrows crossing the symbol,
    which partition the background and corrupt a fill. The flood-filled interior
    plus its outline is the symbol and nothing else.
    """
    from PIL import Image, ImageDraw
    sys.path.insert(0, HERE)
    from measure_reference import SEEDS, SHEET, FILL
    if name not in SEEDS or not os.path.exists(SHEET):
        return None
    grey = Image.open(SHEET).convert("L")
    flat = grey.point(lambda p: 0 if p < 128 else 255).convert("L")
    if flat.getpixel(SEEDS[name]) < 128:
        return None
    ImageDraw.floodfill(flat, SEEDS[name], FILL, thresh=10)
    # The filled interior only. Including ink here would pick up every black
    # pixel on the sheet, not just this symbol's outline.
    region = flat.point(lambda p: 255 if p == FILL else 0).convert("1")
    box = region.getbbox()
    return region.crop(box) if box else None


def cmd_conformance(args):
    with open(INVARIANTS) as fh:
        spec = json.load(fh)
    failures = 0
    print("Symbol conformance against %s\n" % spec["reference"])
    print("  %-13s %-17s %-15s %-15s %s"
          % ("symbol", "aspect", "shape overlap", "height/producer", ""))
    print("  %-13s %-8s %-8s %-7s %-7s %-7s %-7s %s"
          % ("", "render", "ref", "IoU", "min", "render", "ref", ""))

    # The producer is the grid's reference height, so measure it first.
    base_png = os.path.join(OUT, "symbol-producer-bare.png")
    base_height = (esmeasure.geometry(esmeasure.load_mask(base_png))["height"]
                   if os.path.exists(base_png) else None)
    for name, inv in sorted(spec["symbols"].items()):
        png = os.path.join(OUT, "symbol-%s-bare.png" % name)
        if not os.path.exists(png):
            print("  %-13s no render -- run `make render` first" % name)
            failures += 1
            continue
        ours = esmeasure.load_mask(png)
        got = esmeasure.geometry(ours)["aspect"]
        want, tol = inv["aspect"], inv["aspect_tol"]
        aspect_ok = abs(got - want) <= tol

        iou_ok, iou_val, iou_min = True, None, inv.get("iou_min")
        if iou_min is not None:
            ref = reference_solid(name)
            if ref is None:
                iou_ok = False
            else:
                iou_val = esmeasure.iou(ref, esmeasure.interior(ours))
                iou_ok = iou_val >= iou_min

        # Relative height: the guarantee the grid exists to provide.
        ratio_ok, ratio_val = True, None
        want_ratio = inv.get("height_ratio")
        if want_ratio is not None and base_height:
            ratio_val = esmeasure.geometry(ours)["height"] / base_height
            ratio_ok = abs(ratio_val - want_ratio) <= inv.get("height_ratio_tol", 0.05)

        ok = aspect_ok and iou_ok and ratio_ok
        failures += 0 if ok else 1
        print("  %-13s %-8.3f %-8.3f %-7s %-7s %-7s %-7s %s   %s"
              % (name, got, want,
                 ("%.3f" % iou_val) if iou_val is not None else "-",
                 ("%.2f" % iou_min) if iou_min is not None else "-",
                 ("%.3f" % ratio_val) if ratio_val is not None else "-",
                 ("%.3f" % want_ratio) if want_ratio is not None else "-",
                 "ok" if ok else "FAIL", inv.get("note", "")))
    print()
    if failures:
        print("%d symbol(s) outside tolerance." % failures)
        print("Re-measure the reference before changing a tolerance -- see AGENTS.md section 5.")
        return 1
    print("All symbols within the tolerances measured from Odum's sheet.")
    return 0


def cmd_compare(args):
    """Side-by-side: Odum's published symbol beside ours, at matched height.

    The reference crop comes from the same flood-fill that produced the
    conformance targets, so the panel shows exactly what was measured. Output
    feeds the paper's figures as well as human review.
    """
    from PIL import Image, ImageDraw
    sys.path.insert(0, HERE)
    from measure_reference import SEEDS, SHEET, FILL

    if not os.path.exists(SHEET):
        print("reference sheet not found")
        return 1
    grey = Image.open(SHEET).convert("L")
    flat = grey.point(lambda p: 0 if p < 128 else 255).convert("L")

    HEIGHT, GAP = 260, 40
    panels = []
    for name in sorted(SEEDS):
        render = os.path.join(OUT, "symbol-%s-bare.png" % name)
        if not os.path.exists(render):
            print("  skip %s (no render)" % name)
            continue
        # Reference: flood-fill the interior to find the body, then crop the
        # original -- the fill locates the body, the crop keeps the ink.
        work = flat.copy()
        ImageDraw.floodfill(work, SEEDS[name], FILL, thresh=10)
        px = work.load()
        pts = [(x, y) for y in range(work.height) for x in range(work.width)
               if px[x, y] == FILL]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        pad = 3
        ref = grey.crop((min(xs)-pad, min(ys)-pad, max(xs)+pad, max(ys)+pad)).convert("RGB")

        ours = Image.open(render).convert("RGB")
        ours = ours.crop(ours.convert("L").point(
            lambda p: 255 if p < 128 else 0).convert("1").getbbox())

        def fit(img):
            w = max(1, int(img.width * HEIGHT / img.height))
            return img.resize((w, HEIGHT), Image.LANCZOS)

        ref, ours = fit(ref), fit(ours)
        panel = Image.new("RGB", (ref.width + GAP + ours.width, HEIGHT), "white")
        panel.paste(ref, (0, 0))
        panel.paste(ours, (ref.width + GAP, 0))
        dest = os.path.join(OUT, "compare-%s.png" % name)
        panel.save(dest)
        panels.append((name, panel))
        print("  %-13s reference | energese  ->  %s" % (name, os.path.relpath(dest, ROOT)))

    if panels:
        # Three columns: a single stacked column runs to a full page in the
        # paper, which is far more space than the comparison needs.
        margin, cols = 30, 3
        cw = max(p.width for _, p in panels) + margin
        ch = max(p.height for _, p in panels) + margin
        rows = (len(panels) + cols - 1) // cols
        combined = Image.new("RGB", (cw * cols + margin, ch * rows + margin), "white")
        for idx, (_, p) in enumerate(panels):
            x = margin + (idx % cols) * cw + (cw - margin - p.width) // 2
            y = margin + (idx // cols) * ch
            combined.paste(p, (x, y))
        combined.save(os.path.join(OUT, "compare-all.png"))
        print("  combined -> tests/fidelity/out/compare-all.png")
    return 0


def cmd_fonts(args):
    """Check that renders embed the fonts the goldens were built with."""
    probes = [f for f in os.listdir(OUT) if f.endswith("-ports.pdf")] \
        if os.path.isdir(OUT) else []
    if not probes:
        print("no rendered PDFs -- run `make render` first")
        return 1
    probe = os.path.join(OUT, sorted(probes)[0])
    try:
        out = subprocess.run([args.pdffonts, probe], capture_output=True,
                             text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        print("could not run %s: %s" % (args.pdffonts, exc))
        return 1

    missing = [f for f in REQUIRED_FONTS if f not in out]
    for font in REQUIRED_FONTS:
        print("  %-28s %s" % (font, "embedded" if font not in missing else "MISSING"))
    if missing:
        print("\n%s was not embedded in %s."
              % (", ".join(missing), os.path.relpath(probe, ROOT)))
        print("energese.sty falls back silently when tex-gyre is absent, so this "
              "build would produce goldens that do not match anyone else's.")
        print("Install tex-gyre (Debian: texlive-fonts-extra) and re-render.")
        return 1
    print("\nExpected fonts embedded; goldens from this build are comparable.")
    return 0


def cmd_overlay(args):
    """Overlay a rendered diagram on the published figure it reproduces.

    Symbol conformance is measured; whole diagrams are not, and cannot be --
    a 144 dpi capture of a hand-drawn figure has no ground truth to score
    against, and any threshold would be measuring the scan. What an overlay
    gives is the thing a person is actually good at: seeing at a glance which
    components sit where they should, which pathways are missing, and which
    have drifted. It is a review aid, not a test, and nothing fails on it.

    Reference in red, our render in blue, agreement in dark.
    """
    from PIL import Image, ImageChops
    pairs = [("aggregated-economy", "diagram-aggregated-economy")]
    made = 0
    for ref_name, ours_name in pairs:
        ref_path = os.path.join(ROOT, "reference-images", ref_name + ".png")
        our_path = os.path.join(OUT, ours_name + ".png")
        if not (os.path.exists(ref_path) and os.path.exists(our_path)):
            print("  skip %s (missing input)" % ref_name)
            continue

        def inked(path):
            g = Image.open(path).convert("L")
            m = g.point(lambda p: 255 if p < 150 else 0).convert("1")
            box = m.getbbox()
            return m.crop(box) if box else m

        ref, ours = inked(ref_path), inked(our_path)
        # Scale to a common width; the diagrams differ in aspect, and forcing
        # both into one box would hide exactly the drift worth seeing.
        width = 1400
        def fit(m):
            h = max(1, int(m.height * width / m.width))
            return m.convert("L").resize((width, h), Image.LANCZOS) \
                    .point(lambda p: 255 if p > 100 else 0).convert("1")
        ref, ours = fit(ref), fit(ours)
        height = max(ref.height, ours.height)

        canvas = Image.new("RGB", (width, height), "white")
        for mask, colour in ((ref, (215, 40, 40)), (ours, (30, 70, 200))):
            layer = Image.new("RGB", (width, height), colour)
            pad = Image.new("1", (width, height), 0)
            pad.paste(mask, (0, (height - mask.height) // 2))
            canvas = ImageChops.darker(canvas, Image.composite(layer,
                Image.new("RGB", (width, height), "white"), pad))
        dest = os.path.join(OUT, "overlay-%s.png" % ref_name)
        canvas.save(dest)
        made += 1
        print("  %-22s reference red / render blue -> %s"
              % (ref_name, os.path.relpath(dest, ROOT)))
    return 0 if made else 1


def cmd_sheet(args):
    from PIL import Image
    # Rasterise in colour for the sheet. The goldens are greyscale so that a
    # colour-management change cannot invalidate them, but the sheet needs to
    # show the ports in red against the outline.
    for name in sorted(SYMBOLS):
        pdf = os.path.join(OUT, "symbol-%s-ports.pdf" % name)
        if os.path.exists(pdf):
            subprocess.run([args.pdftoppm, "-png", "-r", str(DPI), "-singlefile",
                            pdf, os.path.join(OUT, "colour-%s" % name)], check=True)
    tiles = [(n, os.path.join(OUT, "colour-%s.png" % n)) for n in sorted(SYMBOLS)]
    tiles = [(n, p) for n, p in tiles if os.path.exists(p)]
    if not tiles:
        print("no symbol renders found")
        return 1
    images = [Image.open(p).convert("RGB") for _, p in tiles]
    pad, cols = 24, 3
    cw = max(i.width for i in images) + pad
    ch = max(i.height for i in images) + pad
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cw * cols, ch * rows), "white")
    for idx, img in enumerate(images):
        x = (idx % cols) * cw + (cw - img.width) // 2
        y = (idx // cols) * ch + (ch - img.height) // 2
        sheet.paste(img, (x, y))
    dest = os.path.join(OUT, "contact-sheet.png")
    sheet.save(dest)
    print("Contact sheet: %s (%s)" % (dest, ", ".join(n for n, _ in tiles)))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["render", "regression", "accept",
                                        "conformance", "sheet", "compare", "fonts", "overlay"])
    ap.add_argument("--lualatex", default=os.environ.get("LUALATEX", "lualatex"))
    ap.add_argument("--pdftoppm", default=os.environ.get("PDFTOPPM", "pdftoppm"))
    ap.add_argument("--pdffonts", default=os.environ.get("PDFFONTS", "pdffonts"))
    args = ap.parse_args()
    return {"render": cmd_render, "regression": cmd_regression, "accept": cmd_accept,
            "conformance": cmd_conformance, "sheet": cmd_sheet,
            "compare": cmd_compare, "fonts": cmd_fonts,
            "overlay": cmd_overlay}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
