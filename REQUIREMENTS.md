# Requirements

What `energese` must do, and how each requirement is verified. Every entry names
the check that enforces it; a requirement with no check is marked as such.

For *how* fidelity is defined and measured, see [AGENTS.md](AGENTS.md) §2.
For the current state of the work, see [CLEANUP.md](CLEANUP.md).

---

## 1. Purpose

Render H.T. Odum's Energy Systems Language diagrams from a declarative model,
inside a LaTeX document, faithfully enough that the result can stand as a
figure in the scientific literature.

A diagram must be a *function of its model*: change the model, rebuild, and the
figure follows. Diagrams maintained alongside their models drift from them.

## 2. Authoring

| # | Requirement | Verified by |
| --- | --- | --- |
| 2.1 | A model may be written as JSON, in a file or inline. | `make test` |
| 2.2 | A model may be written directly in TeX with declarative macros. | `make test` |
| 2.3 | Both front ends accept identical key names and produce identical output. | `make parity` |
| 2.4 | Neither front end may hold a capability the other lacks. | `make parity` |
| 2.5 | The symbols are usable as plain TikZ nodes, without the layout engine. | user guide builds |

2.3 is the load-bearing one. It is enforced by rendering equivalent models
through both paths and requiring byte-identical rasters, over three diagrams
including a complete published figure.

## 3. Symbols

| # | Requirement | Verified by |
| --- | --- | --- |
| 3.1 | All of Odum's flow symbols are implemented. | `make conformance` |
| 3.2 | Each symbol's aspect ratio matches the published sheet within tolerance. | `make conformance` |
| 3.3 | Each symbol's interior overlaps the published symbol within tolerance. | `make conformance` |
| 3.4 | Symbols in one diagram are consistently sized, on Odum's relative heights. | `make conformance` |
| 3.5 | A symbol sizes itself to its label rather than clipping it. | `make regression` |
| 3.6 | Outline weight matches the pen weight measured in the reference. | not asserted |
| 3.7 | Every symbol publishes anchors for energy, money and dissipation. | `make regression` |

Tolerances are set by the reference material, not by preference: the available
captures are 144 dpi, so a linear dimension is recoverable to roughly 1–3%.
`tests/fidelity/invariants.json` records each target, its tolerance, and the
measurement it came from.

3.6 is currently a constant (`\energeselinewidth`) chosen from measurement but
not asserted by a test.

## 4. Layout

| # | Requirement | Verified by |
| --- | --- | --- |
| 4.1 | Horizontal position is ordinal in transformity: rank, not value. | `make test` |
| 4.2 | Vertical position derives from a node's role relative to the main chain. | `make test` |
| 4.2a | Vertical placement never depends on node identifiers. | not asserted |
| 4.3 | Explicit coordinates override either axis independently. | `make regression` |
| 4.4 | Pathways pass behind symbols, never across them. | `make regression` |
| 4.5 | Dissipation converges on one ground symbol, outside any system window. | `make regression` |
| 4.6 | Dense diagrams may need per-edge routing. | accepted limitation |

## 4a. Energetic validity

| # | Requirement | Verified by |
| --- | --- | --- |
| 4a.1 | Energy quality does not fall along an `energy` pathway. | `check_energetics` |
| 4a.2 | Sources take no energy inflow; grounds emit none. | `check_energetics` |
| 4a.3 | Every component is reachable from a source. | `check_energetics` |
| 4a.4 | Energy that arrives leaves, as outflow or dissipation. | `check_energetics` |
| 4a.5 | Findings warn by default; `metadata.strict` makes them errors. | `check_energetics` |

`material` pathways are exempt from 4a.1: degraded material moving to a waste or
decomposition store genuinely falls in transformity. Conservation of energy is
**not** checked — it needs quantities the diagram does not carry, and belongs
with the simulation kernel.

## 5. Reproducibility

| # | Requirement | Verified by |
| --- | --- | --- |
| 5.1 | Rendering is deterministic run to run. | `make regression` |
| 5.2 | Any change to rendered output fails the build until reviewed. | `make regression` |
| 5.3 | Accepting a change versions the new reference with the code. | `make regression-accept` |
| 5.4 | Builds embed the fonts the goldens were built with. | `make fonts` |
| 5.5 | Goldens are comparable across machines. | not asserted |

5.5 needs the container image digest pinned; until then goldens are only
strictly comparable within one TeX Live installation. This is the main
outstanding gap in the reproducibility story.

## 6. Distribution

| # | Requirement | Verified by |
| --- | --- | --- |
| 6.1 | Distributable on CTAN. | not yet |
| 6.2 | Documentation ships with the package. | `make docs` |
| 6.3 | The model format is shared with the GSSK simulation kernel. | not yet |

6.1 requires a `.dtx`/`.ins` conversion and a TDS-conformant layout; 6.3 is
designed in `docs/gssk-interop.md` but not implemented.

## 7. Explicit non-goals

- **Simulation.** `energese` draws; GSSK integrates. The shared model format is
  the seam between them.
- **Emergy accounting.** Transformity positions a node; the package does not
  compute or validate emergy. There is no agreed algorithm to validate against,
  so a check would assert a standard that does not exist. The dual energy/emergy
  flow depiction of Valyi's emergy simulator is likewise unsupported.
- **Interactive editing.** The model is text, versioned alongside the document.
- **Engines other than LuaLaTeX.** The layout engine is Lua.
