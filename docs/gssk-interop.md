# GSSK interoperability

Status: **implemented** as `energese.normalise`, which runs ahead of validation
in `energese.render`, so both front ends read GSSK models and neither needed a
new rendering path. Written against GSSK schema v4 (`gssk.schema.json`, title
"GSSK Model (Schema v4)") as read on 2026-09-03, then corrected against a real
file the editor produced (`tests/fixtures/gssk-grass.json`) -- see §7, which
records where the two disagreed.

Goal: one file that both simulates and draws, so a published figure is generated
from the model that produced the results beside it, and the two cannot drift.

---

## 1. Why this is straightforward

The two formats converged independently, because both are formalising the same
language. GSSK and energese already share the top level:

```json
{ "metadata": {...}, "nodes": [...], "edges": [...] }
```

More striking, **GSSK's node type vocabulary is Odum's symbol set**:

> storage, source, sink, constant, interaction, gain, loop_limited, exchange,
> switch, producer, consumer, misc_box, system_frame

That is not a coincidence to be papered over with an adapter; it is the same
notation, and energese should adopt the vocabulary rather than maintain a rival
one.

## 2. What differs

| Concern | GSSK | energese | Resolution |
| --- | --- | --- | --- |
| Edge endpoints | `origin`, `target` | `from`, `to` | Accept both; `origin`/`target` canonical |
| Edge kind | `logic` (`linear`, `interaction`, `ratio`, …) — *how it computes* | `type` (`energy`, `material`, `money_feedback`, `information`) — *how it draws* | Orthogonal. Keep both; derive a drawing default from `logic` + carrier when `type` is absent |
| Node quantity | `value` (state variable) | `magnitude` (symbol scale) | Distinct meanings. Never map `value` to `magnitude` silently |
| Energy quality | *(none)* | `Tr`, drives column placement | Derive when absent — see §4 |
| Presentation | `visual` object | top-level keys | Presentation moves into `visual` |
| Simulation | `config`, `params`, `forcing` | *(none)* | Ignored by energese |

`gain`, `loop_limited` and `switch` are now implemented as symbols and need no
mapping. `exchange` maps to what energese calls `transaction` and `misc_box` to
`box`. `constant` maps to `source`: a fixed input from outside the system is
what Odum's source *is*, and GSSK distinguishes the two only because the kernel
integrates them differently, which is not a distinction the drawing makes.

`sink` is not a mapping at all -- see §7.

`system_frame` is **not implemented**. It should become a system boundary, but
no sample containing one has been seen, and guessing at where the editor keeps a
frame's extent would produce a converter that silently draws the wrong rectangle.
A model carrying one is rejected by name, which is the honest failure.

## 3. The extension point

GSSK's schema sets `additionalProperties: false` on both Node and Edge, so
energese keys **cannot** simply be added — a decorated model would fail
validation. But the schema already reserves exactly what is needed:

```json
"visual": { "type": "object", "additionalProperties": true,
            "description": "UI layout hints. Ignored by the kernel." }
```

So all presentation goes in `visual`, on both nodes and edges:

```json
{ "id": "forest", "type": "producer", "value": 100.0,
  "params": { "k_production": 0.005 },
  "visual": { "label": "Forest", "Tr": 100, "magnitude": 1.2 } }
```

The file stays schema-valid, the kernel ignores `visual`, and energese reads it.
Nothing needs to change in GSSK.

## 4. Deriving transformity

Energese places columns by `Tr`, and GSSK has no such field. Three sources, in
order of precedence:

1. `visual.Tr` if the author supplied it.
2. `metadata.energese.transformity`, a map of node id to value, so a whole
   diagram can be tuned without touching every node.
3. Otherwise **derive it topologically**: longest-path depth from the sources
   along energy and material pathways. This reproduces the qualitative ordering
   Odum's convention expresses — quality increases along the chain — without
   claiming quantitative transformity the model does not contain.

The derived case must be visibly a derivation, not a measurement. It orders the
diagram; it is not an emergy calculation, and the documentation must say so.

## 5. Implementation

`energese.normalise(model)` in `energese-core.lua`, called first thing in
`energese.render`:

```
detect GSSK      -- an edge spelling its ends origin/target; see §8
for each node:   lift node.visual onto the node; map type via GSSK_TYPE;
                 default label to id; leave `value` alone
for each edge:   origin/target -> from/to; lift edge.visual;
                 type := visual.type or DRAW_FROM_LOGIC[logic] or "energy"
drop sinks       -- the node and every pathway into it; see §7
fill missing Tr  -- supplied, then metadata.energese.transformity, then derived
convert coords   -- pixels to units, y flipped; see §7
```

Every rule fills in what is absent rather than overwriting what is present, so a
native energese model passes through untouched even if the detection is wrong.
The coordinate conversion is the one exception -- it would wreck a native model
-- and it fires only on coordinates that came out of a `visual` object.

Both front ends proceed unchanged, so GSSK support costs one function and no new
rendering path. The TeX front end gets it for free.

## 6. Testing

`tests/unit/test_gssk.tex` asserts the rules against a real generator's output:
that the raw file is rejected and the normalised one validates, that endpoints
and labels are carried across, that the sink collapses, that the canvas
coordinates come out in units and the right way up, that transformity is derived
along the chain but never overwrites a supplied one, that `layout = "auto"`
defers to the grid, and that a native model passes through untouched.
`diagram-gssk` is the golden for what it draws.

Still outstanding, and worth doing:

- Every model in GSSK's `examples/` should render without error. That directory
  is the real corpus and exercises types energese has yet to implement — so the
  first run is also the definitive list of what is missing.
- A GSSK model and its hand-written energese equivalent should rasterise
  identically, extending the existing parity check to a third front end.
- Round-trip: a model decorated with `visual` must still validate against
  `gssk.schema.json`. Assert this in CI so an added key cannot silently break
  the kernel's contract.

## 7. What the schema did not say

Three things a real file from the editor settled, none of them visible in the
schema.

**Dissipation is stated in both languages, and carrying both draws it twice.**
GSSK models the heat sink explicitly: a `sink` node with pathways into it.
Energese states the same thing structurally — a storage dissipates, so the
renderer draws the pathway and the ground itself. Convert naively and the
diagram grows a second ground beside the first. So `sink` is not a type to map:
the node is dropped and so is every pathway into it, and energese's own handling
draws what the GSSK model was saying. A component whose type Odum gives no heat
sink — a source, an interaction — loses that statement in the conversion, which
is the convention doing its job rather than an omission.

**Coordinates are in different units and the y axis runs the other way.** The
canvas is in pixels with y increasing downwards; the diagram is in centimetres
with y increasing upwards. Copied across unconverted, a three-node model comes
out 380cm by 453cm — past 575cm TeX abandons the dimension outright — and upside
down, with dissipation above the source it came from. That inverts the one
convention the notation is most emphatic about, and no validator would catch it.
The conversion is 50 pixels to the unit, which is the ratio that makes a typical
editor layout land at the spacing the grid would have chosen; override it with
`metadata.energese.pixels_per_unit`. The author placed those nodes, so the
placement is honoured by default; `metadata.energese.layout = "auto"` throws it
away and lets the transformity grid place the diagram instead.

**Detection cannot key on `metadata.schema_version`.** The editor's output has
no `metadata` at all — it carries `config` and `boundaries`. An edge spelling
its ends `origin`/`target` is the reliable tell, with `config` and a node-level
`visual` as corroboration.

Not handled, for want of a sample: an edge's `visual.ctrl1`/`ctrl2`, which are
Bézier control points where energese takes waypoints the pathway passes
*through*; and the top-level `boundaries` array.

## 8. Open questions

1. Adopt GSSK's names outright (`exchange` for `transaction`, `sink`,
   `misc_box`), keeping the current names as deprecated aliases? Recommended —
   one vocabulary is the point.
2. Should `energese` read GSSK's `config` at all, for example to caption a
   diagram with the integration window it was simulated over?
3. Does GSSK's `carriers` concept need a visual distinction, or is `type` on the
   edge sufficient?
4. Where should the shared schema live once both depend on it?
