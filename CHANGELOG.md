# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) — with the caveat
that while the major version is 0, the rendered output of a diagram is not yet
covered by the compatibility promise. A change to symbol geometry or layout
changes every figure that uses it, and is called out here when it happens.

Each release is archived on Zenodo. The concept DOI
[10.5281/zenodo.22340275](https://doi.org/10.5281/zenodo.22340275) resolves to
the latest; version DOIs are listed in the record's *Versions* box.

## [0.1.0] — 2026-09-06

The first release with the layout engine and the fidelity harness in the state
the documentation describes. **Rendered output changes throughout**: pathways
attach at different points, take different routes, and carry their labels
elsewhere. Diagrams built against 0.0.1 will not be pixel-identical.

### Added

- **Ports.** A symbol's connection ring is its set of attachment points, and a
  port holds one pathway. Named anchors (`energy_in`, `heat_sink`, …) name a
  direction and resolve to the nearest port, so the points a diagram draws and
  the points a pathway attaches to are one set. A second flow arriving at the
  same place takes the next port along rather than being drawn over the first.
  `\energeseport` exposes the allocator to hand-drawn TikZ.
- **Reading GSSK models.** `\renderEnergese` accepts files from the GSSK
  simulation kernel directly, normalised ahead of validation, so one file both
  simulates and draws. `sink` nodes collapse into the package's own dissipation
  handling, and canvas coordinates are converted from pixels rather than
  copied. See `docs/gssk-interop.md`.
- **Semantic grouping.** Interactions and standalone transactions are placed
  against the component they modify instead of taking a column of their own.
  `parent`, `parent_dx`, `parent_dy` and `attach` override it.
- **System window from extents.** `system_boundary: true` now fits the frame to
  what is inside it — sources outside, by Odum's convention, overridable per
  node with `inside` — leaving room underneath for the dissipation funnel.
  `boundary_margin` sets the margin.
- **Automatic placement of pathway labels**, scored against the symbols, the
  other pathways, the dissipation bundle and the frame. Supplying
  `label_options` still places a label by hand.
- **`latexmkrc`**, so an editor's build button (LaTeX Workshop, TeXShop)
  produces what `make` produces. These documents cannot be built by pdfLaTeX.
- **Release metadata**: `LICENSE` (MIT, previously named only in prose),
  `CITATION.cff`, `.zenodo.json` and this changelog.
- Test layers for the above: `test_ports`, `test_routing` and `test_gssk`
  assert the rules where a rendered picture cannot, and six fidelity fixtures
  cover ground no shipped example exercises — port contention, obstacle
  routing, the auto-fitted window, a scaled picture, and a GSSK model.

### Changed

- **Pathway routing is a shortest path through a visibility graph.** The
  previous router cleared one symbol into the next as often as not, and gave up
  at a recursion bound by drawing straight through a symbol — which in this
  notation asserts a connection the model does not contain.
- **Dissipation converges as a delta rather than a spray.** How far each
  tributary drops before turning in is ordered by its distance from the trunk,
  so two of them cannot cross.
- **Pathway labels are set in the package's label font.** They previously
  inherited the surrounding document's, which put a diagram's quantities in the
  body text's serif beside its symbols' sans.
- Obstacle extents account for the fraction of a symbol's width its label may
  occupy. A labelled exchange diamond was previously understated by half.

### Fixed

- **The switch's ports sat up to 19.6% outside its outline.** The radius at a
  given angle is now solved on the actual cubic rather than approximated. As a
  port, a point off the outline is a pathway attached to nothing.
- **Ports were misplaced in any picture drawn with a TikZ `scale`.** The port
  count rode in an anchor coordinate, which the picture's transformation
  scaled: at `scale=0.85` a symbol with twelve ports was read as having ten,
  and dissipation left the corner of a symbol instead of its underside. Every
  golden happened to be drawn unscaled, hence the new `diagram-scaled` fixture.
- An interaction's `west` anchor pointed into the void inside its notch.
- Port allocation depended on the order a model happened to list its edges, so
  the JSON and TeX front ends could render the same diagram differently.
- `mod(index, count) * 360 / count` overflowed pgfmath on symbols carrying 46
  ports or more, killing the anchor with `Dimension too large`.

### Documentation

- `AGENTS.md` records the decisions the engine depends on, each with the
  failure that motivated it.
- `docs/gssk-interop.md` moves from design to implemented, and records the
  three places the GSSK schema and a real file from the editor disagreed.
- The user guide gains the port model, the layout rules, and a chapter on
  reading GSSK models.
- `README.md` is rewritten around the archived release.

### Known limitations

- Goldens are pinned to a TeX Live installation; the container image digest is
  not yet pinned, so a golden mismatch across machines is not necessarily a
  regression (`AGENTS.md` §3).
- GSSK's `system_frame` is not converted, for want of a sample carrying one. A
  model containing it is rejected by name rather than silently mis-drawn.
- Where two symbols stand closer together than a pathway's label is wide, no
  placement is clear and the least obstructed one is used.

## [0.0.1] — 2026-09-05

First archived release: the package, the two front ends, the symbol set, and
the beginnings of the fidelity harness.

[0.1.0]: https://github.com/energese-project/latex-energese/releases/tag/v0.1.0
[0.0.1]: https://github.com/energese-project/latex-energese/releases/tag/v0.0.1
