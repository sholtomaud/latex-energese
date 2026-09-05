# AGENTS.md

Source of truth for this repository: what `energese` is, how fidelity to Odum's
symbols is defined and measured, and the workflow for changing anything that
affects rendered output.

`CLAUDE.md` is additive to this file. Read this one first.

The goal is a CTAN-distributable LuaLaTeX package that reproduces H.T. Odum's
Energy Systems Language symbols and diagrams faithfully, with that faithfulness
enforced automatically rather than eyeballed.

---

## 1. Architecture

Three files carry the package:

| File | Responsibility |
| --- | --- |
| `energese-core.lua` | The model and the layout engine. Parses JSON, builds the model from the TeX macros, computes coordinates, emits TikZ. |
| `energese-shapes.tex` | The Odum symbols as PGF shapes. Geometry and anchors only. |
| `energese.sty` | The user-facing surface: TikZ styles, the two front ends, the macros, and the port allocator (`\energeseport`), which is renderer machinery rather than geometry. |

The rule that keeps this coherent: **there is one model and one renderer.** The
JSON front end and the TeX front end both produce the same Lua table, which
`energese.render` turns into TikZ. Neither front end may acquire a capability
the other lacks, and neither may render anything itself. `make parity` enforces
this by rasterising equivalent diagrams from both paths and requiring the pixels
to be identical.

Anything that changes what a diagram looks like belongs in `energese-core.lua`
(layout, routing) or `energese-shapes.tex` (symbol geometry) — never in a front
end.

**Geometry first, then drawing.** `energese.render` settles every position
before it emits anything that depends on one: the attachment of modifiers, then
the columns and rows, then the obstacle boxes, then the system window, then the
ports, then each pathway's route, then the dissipation bundle, then the labels,
and only then the drawing. The order is forced, not stylistic — a label can only
be kept off the pathways and the frame if the pathways and the frame are already
known, and the frame can only leave room for the dissipation funnel if the
funnel's depth is known. Adding a step that needs to see everything means moving
it into that sequence, not computing it twice.

**Rendering order.** Nodes are emitted once, with their real labels. A symbol
sizes itself to its label, so a placeholder node carrying an empty label is
*smaller* than the one finally drawn — an earlier three-pass renderer did
exactly that, and every edge aimed at the wrong anchor, which showed up as
missing arrowheads and pathways cutting through symbols. Never reintroduce a
placeholder pass.

**Pathways go around symbols, never over or under them.** This is semantics,
not aesthetics: in ESL a line meeting a symbol denotes flow entering that
symbol, so a pathway drawn across an unrelated symbol asserts a connection the
model does not contain. Moving the pathway to a lower layer does *not* fix
this — it still reads as flow into the symbol, merely hidden. An intermediate
version of this renderer made exactly that mistake. The pathway itself must
move, which is what `energese.route` does.

**The router is a visibility graph.** `energese.route` builds the graph whose
vertices are the two endpoints and the corners of every obstacle, inflated by
the clearance a pathway keeps, joins the pairs whose connecting segment cuts no
obstacle, and takes Dijkstra's shortest path over it. For rectangular obstacles
that is *the* shortest available route, since a taut string around boxes bends
only at their corners.

Do not put the greedy step-over router back. Clearing one obstacle at a time to
whichever side deviates less pushes the pathway into the next one as often as
not, gives a staircase of local decisions through a crowded middle, and — since
it bounded its own recursion — ended by drawing straight through a symbol.
`tests/unit/test_routing.tex` pins the case it got wrong: two symbols in a row,
where clearing the first by the smaller deviation lands the pathway in the
second.

Three details in the router that are easy to undo by accident:

- **What must clear the obstacle is the curve, not the polyline.** The drawn
  curve cuts the corners the polyline turns at, so a polyline clearing a symbol
  by a hair yields a pathway that crosses it. `energese.curve_is_clear` samples
  the cubics `smooth_path` will emit, and the router widens the corners it bends
  around until the curve clears too.
- **A box containing an endpoint is not an obstacle for that pathway.** There is
  no way out of a box you start inside, and treating it as one leaves the graph
  disconnected and the router with nothing to report.
- **Visibility is tested against boxes inflated slightly less than the corners
  are.** Otherwise a segment leaving a corner along its own box's edge grazes it
  and counts as blocked.

Remaining priority, after the shortest obstacle-free path: where it costs
nothing, no crossing of another pathway. That one is best-effort and some
diagrams cannot satisfy it.

**An author-bent pathway is checked too.** An edge carrying `bend left=20` was
routed by its author, but a bend that crosses a symbol still asserts a
connection the model does not contain, so it cannot simply be accepted.
`energese.clear_bend` keeps the author's intent — the direction of curvature —
and opens the angle in 8-degree steps until the curve clears; only if no angle
clears does the automatic router take over. The collision test reconstructs
TikZ's own cubic, whose control points lie a third of the chord along the
departure and arrival directions, so it tests what the curve actually crosses
rather than the straight line between endpoints.

Obstacle extents are *estimated* — from `\energeseunit`, the shape's
proportions and a per-character label estimate — because Lua does not know what
TeX will typeset. `energese.half_extent` is the one definition of that estimate,
and everything that needs a symbol's size goes through it: a symbol that is one
size to the router and another to the layout would be routed around a box it
does not fill. `energese.UNIT_CM` must track `\energeseunit`. A node whose
estimate is wrong can override it with `clearance_w` / `clearance_h`. Measuring
extents exactly would mean round-tripping them through the `.aux` file, which is
the obvious next step if the estimate proves too coarse.

The label term is the label's width **divided by the fraction of the outline
that shape lets its text occupy** (`TEXT_FRACTION`, the `fx` each shape passes
to `\energese@fit`). A labelled symbol is wider than its label by exactly that
factor, and taking the label's own width as the symbol's understated a labelled
exchange diamond by half.

**The estimate is a floor, not a target.** Over-estimating spaces symbols
further apart and routes pathways wider; under-estimating draws a pathway
through a symbol. Anything that searches against these numbers — the label
placement especially — will happily take a position whose entire clearance is
estimation error, so it scores against a box slightly larger than the estimate.

---

## 2. What "pixel-perfect" means here

This needs stating precisely, because the obvious reading is not achievable and
chasing it wastes effort.

The reference images in `reference-images/` are **144 DPI screen captures of
printed figures**. Individual symbols on `complete-odum-symbols.png` measure
between 45 and 96 pixels tall. At that resolution a circle's radius is
recoverable to about ±1 px — roughly 1.5–3% — and line weight, curve control
points and stroke joins are not recoverable at all. The captures also carry
scanner artifacts, slight skew, and in `aggregated-economy.png` visible
show-through from the reverse of the page.

Byte-comparing our output against those images is therefore not a well-posed
test, and any threshold that "passed" would be measuring noise.

So fidelity is split into two tiers, each pixel-exact where that is meaningful:

### Tier 1 — Golden-image regression (literally pixel-exact)

The reference is **our own approved output**, committed as PNG. Any change that
alters a rendered diagram fails the build and produces a diff image. Accepting
the change is a deliberate, reviewable act that updates the golden in the same
commit as the code.

This is where pixel-exactness is real, and it is the tier that catches
regressions. It is verified to be sound: rasterised output is byte-identical
run to run, and with `SOURCE_DATE_EPOCH=0` and `FORCE_SOURCE_DATE=1` the PDFs
are byte-identical too.

### Tier 2 — Reference conformance (measured, with tolerances)

Against Odum's originals we assert **geometric invariants measured from the
reference**, not pixels. For each symbol:

- the aspect ratio of its interior;
- the intersection-over-union of the interior region against the reference's,
  after normalising both to a fixed square.

Interiors, not outlines: two identical shapes offset by one pixel share almost
no ink, because the ink is a thin ring. Interiors also make the measure
independent of stroke weight, which differs between a capture and a vector
render and is not what conformance is asking about.

Thresholds are the measured agreement less 0.05, recorded in `invariants.json`
alongside the value they came from. Never loosen one to make a failure pass;
re-measure instead.

Each invariant is extracted from the reference image by script, recorded with
the tolerance the measurement precision justifies, and asserted against our
render. Where a ratio cannot be measured to better than a few percent, the
tolerance says so rather than pretending otherwise.

**Tier 2 tells us the symbol is right. Tier 1 keeps it right.**

---

## 3. Determinism requirements

Tier 1 is only valid if rendering is reproducible. These are not optional:

1. **Pin the engine.** Goldens are only comparable across builds of the same
   TeX Live. The container image digest is the pin; CI and local builds must
   agree. A TeX Live upgrade is a deliberate golden-regeneration event.
2. **Pin the date.** Export `SOURCE_DATE_EPOCH=0` and `FORCE_SOURCE_DATE=1`.
   Verified: without them PDFs differ run to run; with them they are
   byte-identical.
3. **Fix rasterisation.** `pdftoppm -r 300 -gray -singlefile`. The DPI is part
   of the golden's identity; changing it invalidates every golden.
4. **Require fonts strictly.** `energese.sty` currently guards the sans font
   with `\IfFontExistsTF` and falls back **silently** if `tex-gyre` is absent.
   That is correct for a user whose install lacks it and fatal for reproducible
   goldens: the same source renders differently on two machines. Regression
   builds must assert the font resolved, and fail loudly if not. Verify with
   `pdffonts` — `TeXGyreHerosCondensed-Regular` must appear embedded.
5. **No system font lookup.** Everything must come from the TeX tree, never
   from `fontconfig`, or output depends on what the host happens to have
   installed.

`make fonts` enforces requirement 4 by checking `pdffonts` output for
`TeXGyreHerosCondensed`, and runs as part of `make check`. Requirement 1 is
**not yet enforced**: the container image digest is unpinned, so goldens are
strictly comparable only within one TeX Live installation. Pin it before
treating a golden mismatch across machines as a real regression.

---

## 3a. Layout decisions the engine makes on its own

**Modifiers are attached, not placed.** An interaction is where two flows
combine on their way into the thing they drive, and Odum draws it against that
thing; a standalone transaction is the same kind of annotation on a pair of
parties. Both are children in a compound graph: `energese.attach_modifiers`
locks them to a parent by a fixed offset and they take no part in the column or
row algorithms — neither claiming a column of their own nor pushing a sibling
out of a row.

The offset follows the flow. A child that feeds its parent sits upstream of it,
one fed by its parent sits downstream; a modifier drawn on the wrong side
reverses the direction its pathway reads in. The gap is half a column or what
the two symbols need to stand clear of each other, whichever is larger — a
fixed fraction of the column buried a labelled diamond's left vertex inside its
consumer. The model overrides all of it: explicit `x`/`y` is never touched,
`parent` names the component, `parent_dx`/`parent_dy` set the offset, and
`attach=false` opts out.

**Dissipation converges as a delta.** A tributary's lane is *how far it drops*
before turning in, assigned by reach: the component nearest the trunk turns in
highest, the furthest lowest, so the further one runs below and outside the
nearer one all the way to the junction they share. Routing each one
independently, which is what this replaced, brought them into the junction from
all directions and they crossed on the way; dissipation pathways that cross read
as pathways meeting where nothing joins.

Two ways of expressing that lane are wrong, and both were tried:

- **Not as a waypoint.** A point to turn at puts a corner mid-pathway, and the
  tangent at an interior waypoint is the chord spanning its neighbours — which
  at a near-right-angle turn points back the way the pathway came and bulges the
  curve out sideways before it can turn.
- **Not with a vertical arrival.** Requiring every tributary to reach the
  junction pointing straight down makes the nearer ones dip below the further
  ones on the way, and they cross after all. Odum's tributaries meet the
  junction at an angle; the *trunk* is what leaves it vertically.

Not a horizontal bus: the tributaries converge on a *point* and one trunk
carries the bundle to the ground. A floor line collecting them would draw
dissipation as flow into a surface, which is not what Odum's figures show and
not what the accounting says.

**The system window encloses extents, not centres.** Everything is inside it
except the sources — Odum's convention, since a source is an input from outside
— and a node overrides that with `inside`. The frame sits a margin outside the
extents of what is inside, labels included; measuring centres and padding by
half a column makes the margin a function of the widest symbol in the diagram.
It also leaves room *underneath* for the dissipation funnel, which converges
inside the window with only its trunk crossing the frame. A frame fitted to the
symbols alone cuts across that funnel and the tributaries sag out of the window
and back in.

**Pathway labels are placed by search.** A quantity written across a symbol,
another pathway, the dissipation bundle or the frame is unreadable, so
`energese.place_edge_labels` scores the placements TikZ can express — a fraction
along the path, above or below, at one of a few distances clear — against all of
those and the labels already placed, and takes the best. Ties go to the
placement nearest the default, because a label that moves without cause is one
the reader has to hunt for. An author who writes `label_options` has placed the
label, and it is left alone.

Two things not to change without reading this first:

- **The search is an enumeration, not an annealer.** Goldens require
  reproducibility (section 3), and the candidate set is not a discretisation of
  a continuous space — it *is* what TikZ can express relative to a path. A
  position it cannot express has to be given absolutely, and an absolutely
  placed label stops travelling with its pathway when the layout moves.
- **Pathway labels use `\energeselabelfont`**, like every other label the
  package places. Inheriting the document's font put a diagram's quantities in
  the body text's serif beside its symbols' sans, and made a label's size
  something Lua could not estimate at all, since it depended on a document it
  cannot see.

Where two symbols stand closer together than a label is wide, no candidate is
clear and the least bad one is taken. `aggregated-economy` has such a case: the
`6000` label sits on the system frame because every alternative sits on a
symbol. That is the layout being tight, not the placement being wrong.

---

## 4. Test layers

Five layers, cheapest first. Every one must be runnable by a single `make`
target and wired into CI.

| Layer | Question it answers | Target |
| --- | --- | --- |
| Unit (Lua) | Does the layout engine compute the right coordinates? | `make test` |
| Compile | Does every document build without error? | `make test` |
| Parity | Do the JSON and TeX front ends agree exactly? | `make parity` |
| Symbol regression | Has any individual symbol's rendering changed? | `make regression` |
| Diagram regression | Has any whole diagram's rendering changed? | `make regression` |
| Conformance | Does each symbol match Odum's geometry within tolerance? | `make conformance` |

All six layers exist and are wired into `make check`. They were built because
the earlier suite could not catch a wrong symbol, and demonstrably did not: the
producer was drawn rounded-left/pointed-right and the consumer with the wrong
topology entirely, while `tests/unit/test_shapes.tex` rendered both on every run
without complaint, because it only checks that compilation succeeds.

Conformance caught the consumer immediately — rendered aspect 1.435 against a
measured reference of 0.877 — which is the case for keeping this layer.

Supporting targets: `make sheet` builds a contact sheet for human review,
`make compare` builds side-by-side reference/render panels, and
`make measure-reference` re-derives the targets in `invariants.json` from Odum's
sheet. `make regression-accept` promotes renders to goldens, and is the only
sanctioned way to change one.

### Symbol regression harness

One minimal document per symbol, rendered in isolation at a fixed size with a
fixed label, so a symbol's geometry is tested independently of any diagram it
appears in. Each produces a golden PNG. A contact sheet assembling all of them
is generated for human review — the machine catches change, a person catches
*wrong*.

Coverage must be per-symbol and per-port: a symbol test that only renders the
outline will not catch a port that has drifted off it. The `-ports` fixture
marks every port the symbol declares — the count read from its own `ringcount`,
not a fixed 48, so a wrong count cannot hide behind the repeats — and marks
nothing else, because the ring is the whole set of places a pathway can attach.

`tests/unit/test_routing.tex` covers the layout engine at the Lua level, where
a picture cannot: that an unobstructed pathway is left straight, that an
obstructed one clears the obstacle *and* clears it as a curve, that the detour
is taut rather than a staircase, that a corridor of two symbols is cleared at
once, that a box containing an endpoint is not treated as an obstacle, that
routing is deterministic, that dissipation lanes nest by reach, that a modifier
attaches upstream of what it drives and claims no column, and that the system
window fits extents with the sources outside. Three fixtures cover the same
ground as pictures: `diagram-obstacle-routing`, `diagram-auto-boundary` and
`diagram-port-contention`, none of which any shipped example exercises.

Port *allocation* is covered twice over. `tests/unit/test_ports.tex` asserts the
rules and raises a TeX error when one breaks: an axis anchor lands on its own
port, a second pathway gets a different one, a third is pushed further out
rather than back onto the first, a ringless shape keeps its named anchor, and a
reset frees the claims. `diagram-port-contention` is the golden for what that
looks like — seven pathways through one consumer, all asking for the two anchors
on its horizontal axis.

---

## 4a. The implied syntax of ESL, and what this package decides

Odum's Energy Systems Language has no formal grammar or semantics. Building a
renderer forces decisions the language leaves implicit, and those decisions are
part of the package's contribution rather than incidental to it. Record them
here; do not change one without changing this section.

**Horizontal placement is ordinal transformity.** Distinct `Tr` values are
sorted and mapped to consecutive columns at equal spacing, so `Tr` of
1, 100, 2000, 10000 becomes columns 1, 2, 3, 4. Neither linear nor logarithmic:
transformity spans orders of magnitude, so linear placement is unusable, and a
logarithmic scale would assert a metric the language never defines. Rank
preserves the only thing the implied syntax actually claims — the ordering.
Nodes sharing a `Tr` share a column, which makes a column an equivalence class
of energy quality.

**Power is not the vertical variable, and cannot be.** Along a transformation
chain empower is approximately conserved: transformity rises *because* available
power falls, since Tr is emergy per unit available energy. Available power is
therefore already determined — inversely — by horizontal position. Encoding it
again on the vertical axis would be redundant where the two agree and
contradictory where they do not. This was considered and rejected on those
grounds; do not reintroduce it.

**The vertical axis carries no quantity, but it is not arbitrary either.**
Nothing in ESL assigns a magnitude to height. Odum's own figures nonetheless
place things vertically by their role relative to the main transformation
chain, and `derive_layer` recovers that from the graph:

The rule is the horizontal ordering applied *locally*: vertical distance from
the chain tracks transformity relative to the chain. The energy hierarchy
therefore runs bottom-left to top-right.

| Layer | Rule |
| --- | --- |
| spine (y=0) | on the longest chain of **energy** pathways |
| above | higher transformity than the chain node it connects to — a high-quality input, a controller, or a higher-quality product |
| below | receives from the chain at equal or lower transformity — dissipation, decomposition, waste |
| fanned | a lower-quality input, which is unattested in Odum's figures, and anything else unclassifiable; declaration order, beyond the rows already used |

The spine is built from `energy` pathways only. Counting `material` let a waste
store capture the spine and sit on the axis when it belongs below it; the
fallback to energy-plus-material applies only when a model has no energy
pathways at all.

Two empirical results support this rule, and both are worth re-running if it is
ever changed:

- With every hand-placed coordinate stripped from `examples/aggregated-economy.json`,
  the engine puts the high-transformity `fuels` source **above** the chain
  unprompted — reproducing Odum's own placement of Fuels and Minerals entering
  from the top rather than the side.
- With hints *and* geometry stripped from `tests/fixtures/complex_industrial.json`,
  the rule recovers the hand-written `decomposition` annotation on `waste` from
  transformity alone. It places `economy` on the chain rather than above, which
  is defensible — it is the terminal high-quality node of the energy chain — and
  the explicit hint still overrides.

This is why Fuels and Minerals enters Odum's aggregated economy from the *top*
rather than the left, despite being a high-transformity source. `layer_hint`
(`control`/`decomposition`) names a layer explicitly and wins over the derived
one, including over spine membership. `y_gravity` nudges; explicit `y` overrides
everything.

Fan order is **declaration order, never alphabetical**. Sorting by id made the
layout depend on what nodes were called, so renaming one moved others.

**Dissipation converges inside a system window.** Where a window exists the
heat pathways meet just inside it and a single line crosses the frame to the
ground outside. Letting each pathway cross separately shreds the boundary and
misstates the accounting: what leaves the system is one aggregate flow of used
energy, not several.

**The ground is not in the quality ordering.** `ground` carries no `Tr` — it is
a terminator, not a component. Placing the heat sink at the bottom centre
therefore does not violate the horizontal syntax; dissipation going down is the
vertical convention.

## 4c. Exchanges

Odum's exchange is one transaction with two coupled sides: goods pass one way,
money the other, and the diamond is where they meet. Drawing them as two
independent pathways that happen to pass near a diamond looks similar and says
something weaker — that a payment and a delivery both occurred, rather than that
they are the same transaction.

A `transaction` node naming a `seller` and a `buyer` therefore expands into four
half-pathways:

```
seller --energy--> diamond --energy--> buyer
buyer  --money---> diamond --money---> seller
```

`energese.expand_exchanges` runs **before** validation looks at the edges, so
the synthesised legs are checked, routed and drawn exactly like declared ones
and nothing downstream needs to know they were generated. `energy_label` and
`money_label` caption the two sides.

**An exchange is a marker on a pathway, not a component in it.** Goods run
seller to buyer as ONE continuous pathway and the diamond rides it at the
midpoint, rotated to the flow and unfilled, so the lines cut straight through
the glyph. That is exactly what every other symbol forbids (§ on routing), and
the exception is principled: an exchange annotates a coupling, it does not
transform anything, so there is nothing to flow *into*. Consequences that follow
and are easy to get wrong:

- it carries no transformity, so `validate_node` exempts it;
- it dissipates nothing, so it is excluded from the heat-sink bundle even though
  its glyph is a `transaction`, which otherwise does dissipate;
- it is not an obstacle, or routing would push a pathway off its own marker;
- it is never emitted as a standalone node, so nothing may be anchored to it.

The legs run tightly parallel, money just outside goods, so the pair reads as
one transaction rather than two coincidental pathways.

The bend directions look inconsistent and are not: `bend left` is relative to
direction of travel, and the money leg runs opposite to the goods, so matching
`bend left` on both bows them to opposite sides and opens a lens between them.
`bend right` on the return leg puts both bows on the same side; the larger angle
sets the gap.

A default money route would instead arc the payment over the whole diagram,
which is right for a long feedback loop and wrong for the two legs of one sale.

## 4d. Whole-diagram overlay

`make overlay` puts a rendered diagram over the published figure it reproduces,
reference in red and render in blue. It is a **review aid and not a test**:
nothing fails on it, and nothing should. A 144 DPI capture of a hand-drawn
figure has no ground truth to score against, so any threshold would be measuring
the scan — the same argument as §2. What it gives is the thing a person is good
at: seeing at a glance which components sit where they should, which pathways
are missing, and which have drifted.

It has already earned its place. It exposed that rendered symbols were 0.35x the
relative size of Odum's, and chasing that number surfaced a real regression:
`source` and `storage` compute their radius directly and had been missed when
`energese magnitude` replaced TikZ's `scale`, so they silently ignored
magnitude. Symbol conformance passed throughout, because that measures a bare
symbol in isolation and magnitude does not enter.

## 4b. Energetic checks, and their limits

Odum's motivation for ESL was that scholars build models which are energetically
invalid. `energese.check_energetics` says what a renderer can say about a model
without leaving the diagram:

1. Energy quality must not fall along an `energy` pathway.
2. Sources take no energy inflow; grounds emit none.
3. Every component is reachable from a source.
4. Energy arriving somewhere leaves, as outflow or as dissipation.

Findings are **warnings**, because a diagram breaking a convention is often
still worth drawing; `metadata.strict` makes them errors.

Two exclusions are deliberate and must not be quietly relaxed:

- **`material` pathways are exempt from check 1.** Degraded material moving to a
  waste or decomposition store genuinely falls in transformity — that is what
  decomposition *is*. Applying the rule to `material` produced a false positive
  on `tests/fixtures/complex_industrial.json`.
- **Conservation is not checked.** Balancing inflow against outflow needs
  quantities, and `volume` is a line width, not a flux. That belongs with the
  simulation kernel — see `docs/gssk-interop.md`.
- **Emergy is not checked at all.** There is no agreed algorithm, so a check
  would assert a standard that does not exist. `Tr` positions a node; the
  package neither computes nor validates emergy.

## 5. Workflow for changing rendered output

Follow this exactly. It is the only way a geometry change stays reviewable.

1. **Measure first.** If the change is meant to match Odum, extract the target
   ratio from the reference image with a script and record the number. Do not
   adjust geometry by eye against a rendered PNG.
2. **Change the geometry** in `energese-shapes.tex`, or the routing in
   `energese-core.lua`.
3. **Run `make check`.** Expect regression failures; that is the point.
4. **Review every diff image.** A diff you cannot explain is a bug, not a
   golden that needs updating.
5. **Run `make conformance`** to confirm the change moved *towards* the
   reference rather than merely somewhere else.
6. **Accept deliberately** with `make regression-accept`, which regenerates the
   goldens.
7. **Commit code and goldens together.** A commit that changes one without the
   other is not reviewable.

### The trap to avoid

Do not tune a symbol until a specific diagram looks right. Symbols are shared;
the diagram that looks better may be the only one that does. Fix the symbol
against its own measured reference, then fix the diagram's layout separately.

---

## 6. Symbol reference

Odum's canonical set is `reference-images/complete-odum-symbols.png`.
Implemented so far:

| Type | Geometry | Heat sink |
| --- | --- | --- |
| `source` | Circle | no |
| `storage` | Circle with a flattened, peaked top | yes |
| `producer` | Rectangle closed by a semicircle on the **right** | yes |
| `consumer` | Hexagon, pointed **left and right** | yes |
| `transaction` | Diamond (Odum's "exchange") | yes |
| `interaction` | Pointed right, notched left | no |
| `gain` | Right-pointing triangle (constant-gain amplifier) | yes |
| `loop_limited` | Rectangle whose right side bows outward | yes |
| `switch` | Square with all four sides bowed inward | yes |
| `box` | Plain rectangle | no |
| `text` | Unboxed label; routing waypoint | no |
| `ground` | Fixed-size heat-sink terminator glyph | n/a |

Sources and interactions carry no heat sink by Odum's convention. `text`, `box`
and `ground` are plain TikZ shapes with no `heat_sink` anchor at all — asking
for one is a hard TeX error, so `energese.HAS_HEAT_SINK` gates it.

All of Odum's flow symbols are implemented. `reference-images/crop-harvest.png`
additionally uses sensor and valve glyphs that do not appear on the canonical
sheet; those remain unimplemented, which is why it has no example.

Symbol outlines use `\energeselinewidth` (0.9pt), matching the constant pen
weight measured in the reference: a steady 2px at 144 DPI regardless of symbol
size, so the weight is absolute, not proportional.

Every symbol sizes itself to its label. `energese@measure` derives half-width
and half-height from `\pgfnodeparttextbox` plus inner separation, clamped
against `minimum width`/`minimum height`, and each shape grows its outline
around that rectangle.

**Shape is invariant; the label gives way.** A symbol holds its canonical
aspect at every size. Widening a hexagon to swallow a long label makes it read
as a different symbol, so each shape declares its measured aspect R and the
fractions (fx, fy) of its outline the text may occupy, and `\energese@fit`
returns the smallest outline at aspect R that contains the label. Verified:
consumers carrying `R`, `Industry`, a two-line label, and magnitude 1.5 all
measure 0.874-0.880 against a canonical 0.877.

Do not reintroduce an aspect *cap*. An earlier version let a wide label flatten
the hexagon up to a limit, which merely bounded the distortion instead of
removing it.

**`energese magnitude` scales the symbol, never the label.** TikZ's `scale` on a
node takes the text with it, so two symbols of different magnitude carrying the
same words came out in different type sizes. The key sets `\energesemagnitude`,
which `\energese@fit` multiplies into the outline only.

**The grid.** Each shape grows from its label at its own rate — a producer at
2.0x the text half-height, a consumer at 3.23x, a gain at 5.2x — so sizing them
independently makes identical labels produce wildly different symbols.
`\energeseunit` is one grid cell, and each style's `minimum width`/`minimum
height` is set to the multiple of a cell at which that symbol's bare form lands
on Odum's measured relative height. Short labels fall inside the floor and every
symbol sits on the grid; an oversized label grows its own symbol. The
`height_ratio` invariant asserts this still holds.

Do not hand-tune a `minimum size` to make one diagram look right: it moves that
symbol off the grid everywhere. Change `\energeseunit`, or re-derive the
multiple from the measured ratio.

Anchor conventions: energy enters at `energy_in` on the left and leaves at
`energy_out` on the right; money moves through `money_in`/`money_out` in the
upper half; dissipation leaves through `heat_sink` at the bottom.

**The connection ring is the port set.** Points spaced a constant distance
apart along the outline, indexed `ring0` at 0 degrees and counting
anticlockwise. A pathway attaches to one of them and to nothing else.

The named anchors (`energy_in`, `money_out`, `heat_sink`, …) are *not* a second
set of points. They name a *direction* — where a kind of flow belongs, because
that is where Odum draws it — and `\energeseport` resolves each to the port
nearest it. Anchors that were free to sit between ports would put a pathway
where the symbol offers no connection, and would make occupancy unanswerable:
the whole point of one set is that "this port is taken" means something.

**A port holds one pathway.** Two flows attached at the same point are drawn as
one line leaving the symbol, which understates how many pathways there are and
hides which of them the arrowhead belongs to. The second claimant takes the next
port along, on the side it approaches from. Dissipation is reserved first,
before any pathway: Odum draws used energy leaving downwards and the heat-sink
drop is measured from the symbol's underside, so that port is not negotiable.

**Allocation must not depend on declaration order.** The first claim on a
contested port wins, so the order in which ports are granted decides the
picture. Granting them as each pathway is drawn made two identical models
render differently for listing their parts in a different sequence — which
`make parity` caught, since the JSON and TeX versions of `aggregated-economy`
declare their exchanges in a different order and the expansion appends the
resulting pathways accordingly. `energese.port_requests` therefore orders them
geometrically: pathways contending for one anchor are served from the middle of
their fan outwards (nearest the fan's circular mean first), which is both
order-independent and the condition for the fan not to cross itself.

Spacing is by arc length (`\energeseanchorpitch`, 3mm), never by angle. Equal
angular divisions would separate points further on a large symbol than a small
one, so a coupled pair would split by a different amount at each symbol it met.
Constant spacing makes the gap a property of the diagram, at the cost of a
variable count per symbol — which is the intended trade. Indices past the ring's
last port repeat earlier positions exactly; wrapping the *angle* instead makes
later indices precess into the gaps and destroys the spacing.

**The count is rounded to a multiple of four**, which puts a port exactly on
each axis — where `energy_in`, `energy_out`, `heat_sink` and the feedback
anchors sit, so quantising those moves them nowhere. The price is that the pitch
is nominal to within one port in four; the price of *not* doing it was an
interaction whose inflow attached half a pitch up the notch edge instead of at
its apex, and a leftover fraction of a turn dumped as one wide gap at the wrap.
`ringcount` publishes the count as an anchor, since PGF offers no other way to
read a computed quantity out of a shape: it rides in a coordinate offset from
the centre. **Read it against `ringunit`, never on its own.** An anchor goes
through the picture's transformation like any other coordinate, so under
`scale=0.85` a count of 12 comes back as 10.2 — and the allocator, quantising
onto a ring of ten points the shape had drawn as twelve, put the heat-sink port
at 240 degrees instead of 270 and dissipation left the corner of the symbol.
Taking the count as the *ratio* of the two offsets cancels the transformation.
Every golden happened to be drawn unscaled, which is why nothing caught it and
why `diagram-scaled` now exists; the paper's own figures are drawn at 0.85.

Each shape supplies a radius-at-angle macro, and every one of them is exact or
converged. The switch's bowed side is solved rather than approximated: in the
box-normalised frame the four cubics collapse to `X = 1.0875u - 0.0875u³`,
`Y = 0.715 + 0.285u²`, and three Newton steps from `u = m` put the point on the
curve to better than 0.05%. The closed form it replaces — box radius ×
`(0.715 + 0.285 sin⁴2θ)` — ran up to **19.6%** outside the drawn outline
between the axis and the corner, which as a port means a pathway attached to
nothing. The interaction's notch, long marked approximate here, is in fact
exact: the notch replaces the left edge rather than cutting a region that has
one, so `1/max(...)` returns the true boundary. Checked against the sampled
polygon at 0.1° steps and four aspect ratios: 0.000%.

Four pgfmath traps cost real time here and will recur:

- it saturates near 16384 and evaluates left to right, so `index * 360 / count`
  overflows on any symbol with 46 ports or more before the division can rescue
  it, and the anchor dies with `Dimension too large` — divide first, and
  parenthesise;
- `?:` evaluates **both** branches, so a guard does not stop `sqrt()` receiving
  a negative discriminant; clamp inside the root instead;
- a length register must be read as `\the\length` inside an expression;
- `pt` cannot be hung on the result of a function call — resolve to a plain
  number first.

**Every anchor must lie on the symbol's outline.** A connection port set inside
the glyph makes a pathway appear to start from nowhere, and one set outside
leaves a visible gap. An interaction's `west` was such a case: due west of that
symbol is the void inside the notch, so `west` now returns the notch apex, which
is the westmost point the symbol actually has. The same applies to anything the renderer derives from an
anchor: the heat-sink drop is measured from the symbol's underside, not its
centre, because a drop shorter than the half-height ran back up inside the glyph.

**All pathways look alike.** One width (`\energeseflowwidth`) and one arrowhead,
whether the pathway ends at a symbol or at the ground — they are all flows, and
drawing dissipation differently implies it is something else. The arrowhead is
`Triangle`, not `Stealth`: Odum's pen drew a blunt solid head. `volume` on an
edge is the one sanctioned override, for showing relative flow.

**Labels.** A node carries `label` (friendly) and `short_label` (Odum's
nomenclature — Q for storages, X and J for sources and flows), and
`metadata.label_mode` picks between them. A label larger than its grid cell is
placed outside the symbol rather than inflating it, and a displaced label joins
the obstacle set so pathways route around the text too.

---

## 7. Building

`lualatex` is not required on the host. `make` accepts an engine override:

```bash
make check LUALATEX=/path/to/wrapper.sh
```

A container wrapper is one line:

```bash
exec container machine run -n ubuntu-latex -w "$PWD" lualatex "$@"
```

**Building from an editor.** Anything that drives the repository through
latexmk — LaTeX Workshop, TeXShop, a bare `latexmk` — reads `latexmkrc` at the
repository root, which sets the two things such a build otherwise gets wrong:

- **The engine is LuaLaTeX.** `energese.sty` calls `\directlua`; the layout
  engine *is* a Lua program, and pdfLaTeX does not degrade, it stops. The rc
  sets `$pdf_mode = 4` for callers that let latexmk choose, *and* redefines
  `$pdflatex` to run `lualatex`, because a caller passing `-pdf` on the command
  line would otherwise override the mode back (LaTeX Workshop's stock latexmk
  arguments do exactly that).
- **The package is at the root; the documents are in `docs/`.** Built in place —
  which is what latexmk's `-cd` does — TeX looks in `docs/` and reports
  `File energese.sty not found`, which reads like a missing dependency rather
  than a search path one directory short. The rc adds the root to `TEXINPUTS`
  and `LUAINPUTS`, by absolute path derived from its own location.

`make` does not read that file; the Makefile passes both settings itself. The
rc exists so an editor's build button produces the same document.

**Two builds must not share an output directory.** `make docs` writes
`docs/article.log` through the container, and so does an editor build of the
same file. Run them at once and one of them dies with
`I can't write on file 'article.log'` — which looks like a permissions fault and
is not one. Nothing in the repository serialises them; if that error appears out
of nowhere, check whether a `make` is running before looking anywhere else.

**Known trap with the `container` CLI:** flags passed as direct arguments work
fine, but `--`-prefixed flags *inside* a `bash -c` string are consumed by
`container`'s own argument parsing. `container machine run ... bash -c 'lualatex
--interaction=nonstopmode file.tex'` silently runs a bare interactive
`lualatex`, reads EOF, and exits 0 having produced nothing. Pass flags as direct
arguments, or put the commands in a script file and run `bash /path/script.sh`.

---

## 8. GSSK interoperability

The model format is being standardised on GSSK (General Systems Simulation
Kernel), so one file both simulates and draws. The two formats converged
independently -- GSSK's node type vocabulary *is* Odum's symbol set -- so this
is adoption of a shared vocabulary rather than an adapter.

The binding constraint: GSSK's schema sets `additionalProperties: false` on Node
and Edge, so energese keys cannot be added to them. Presentation goes in the
`visual` object, which the schema already reserves and the kernel ignores.

`energese.normalise` implements it: it runs first thing in `energese.render`,
rewrites a GSSK model into an energese one, and leaves a native model alone. Two
of its rules are not field mappings and will look like bugs if you meet them
without knowing why:

- **`sink` nodes are dropped, and so is every pathway into them.** GSSK states
  dissipation explicitly; energese states it structurally, by knowing that a
  storage dissipates and drawing the pathway and the ground itself. Carry both
  and the diagram grows a second ground beside the first.
- **Canvas coordinates are converted, not copied.** GSSK's are pixels with y
  increasing downwards; a diagram is centimetres with y increasing upwards.
  Copied across, a three-node model comes out 380cm by 453cm — past 575cm TeX
  abandons the dimension — and upside down, with dissipation above its source.

Detection keys on an edge spelling its ends `origin`/`target`. Not on
`metadata.schema_version`, which `docs/gssk-interop.md` originally proposed: the
editor's output carries no `metadata` at all.

`docs/gssk-interop.md` holds the field mapping, the transformity-derivation
rule, what the schema did not say, and the open questions. Read it before
touching the JSON front end.

## 9. The paper

`docs/article.tex` drafts a submission to *Ecological Modelling* announcing the
CTAN release. Two rules:

- **Its figures are generated by the test harness**, not drawn by hand. `make
  article` runs `compare` and `sheet` first. A figure showing that the symbols
  match Odum's originals must come from the same code that checks it, or the
  paper is asserting something its own tooling does not verify.
- **Numbers in the paper come from `make conformance`.** If a tolerance or a
  measured value changes, Table 1 changes with it. Do not hand-copy figures that
  the harness prints.

Prose marked `[OUTLINE]` is a plan of what a section must argue, not draft text.

## 10. CTAN packaging

Distribution on CTAN is the goal, and it constrains the layout:

- Source moves to a documented `.dtx` with a `.ins` installer; `energese.sty`,
  `energese-core.lua` and `energese-shapes.tex` become generated artifacts.
- The directory tree becomes TDS-conformant.
- `docs/energese_user_guide.pdf` **stays tracked** — it is the package
  documentation CTAN distributes, not incidental build output.
- A release workflow builds, tests, and packages the TDS zip.
- Licence and version metadata must be consistent across `.sty`, `.dtx` and
  `README.md`.

Until the `.dtx` conversion happens, treat the three source files as canonical
and do not hand-edit anything that would become generated.

---

## 11. Conventions

- Comments explain *why*, and are worth writing where a choice is not obvious
  from the code. `energese-shapes.tex` carries the derivations for each symbol's
  proportions; keep them accurate if you change the numbers.
- Routing (`bend`, `out`, `in`, `looseness`) belongs to the edge, never to a
  TikZ style. Baking routing into `energese money_feedback/.style` is what
  inflated every money arc into a full circle.
- New keys must work identically in both front ends, with the same name.
  `energese-core.lua`'s `NUMERIC_KEYS` needs updating for any new numeric key,
  or the TeX front end will pass it through as a string.
- Never edit a golden image by hand.
