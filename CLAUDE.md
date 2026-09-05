# CLAUDE.md

**Read [AGENTS.md](AGENTS.md) first.** It is the source of truth for this
repository: architecture, the definition of pixel-perfect fidelity and how it is
measured, determinism requirements, the test layers, and the workflow for
changing rendered output. Everything below is additive.

## Working here

- **There is no `lualatex` on this Mac.** A `brew upgrade` of BasicTeX was
  interrupted and left `/usr/local/texlive/2026basic` missing, so
  `/Library/TeX/texbin` is a dangling symlink. Build through the `ubuntu-latex`
  container machine instead — see the wrapper in AGENTS.md §7. Do not suggest
  reinstalling BasicTeX as a prerequisite for getting work done; the container
  is the working path.

- **Verify the `container` argument trap before concluding a build "passed".**
  `--`-flags inside a `bash -c` string are eaten by `container`'s own parser,
  and the result is a bare interactive `lualatex` that exits 0 having produced
  nothing. An `EXIT=0` with no log output means the command never ran. Pass
  flags as direct arguments, or run a script file.

- **A green build is not a correct diagram.** Every example compiled with zero
  errors while the producer and consumer symbols were the wrong shape entirely.
  Compilation success proves almost nothing about output. Look at the rendered
  PNG, and compare it against `reference-images/`.

- **Measure the reference; do not eyeball it.** When matching Odum's geometry,
  extract the ratio from the reference image with a script and state the number.
  `reference-images/` is 144 DPI, so symbol measurements are good to roughly
  1.5–3% and no better — say so rather than implying more precision.

- **Check both front ends after any change to the model or renderer.**
  `make parity` rasterises the JSON and TeX versions of the same diagram and
  requires identical pixels. It is the guarantee that the two authoring paths
  have not silently come apart.

- **Scratch files go under `$HOME` or `temp/`.** Paths outside the shared home
  mount are invisible inside the container, so a probe in `/tmp` on the Mac will
  not behave like one inside the machine. `temp/` is git-ignored and holds
  superseded files; nothing there is shipped.

## Reporting

- Say what was verified and how. "Tests pass" is worth little; "9/9 suites and
  both parity pairs pass, built in the container" is checkable.
- Distinguish *compiles*, *renders*, and *matches the reference*. They are three
  different claims and only the third means the work is done.
- When a fix reveals a second, pre-existing bug, say so plainly rather than
  folding it into the first.

## Do not

- Do not hand-edit golden images, or regenerate them to make a failure go away
  without reviewing the diff.
- Do not tune a symbol's geometry until one particular diagram looks right.
  Symbols are shared; fix the symbol against its own measured reference and the
  diagram's layout separately.
- Do not put routing (`bend`, `out`, `in`, `looseness`) into a TikZ style.
- Do not add a capability to one front end without the other.
