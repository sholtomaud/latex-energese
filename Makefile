# energese -- build entry point.
#
# Everything runs through lualatex with TEXINPUTS pointed at the repository
# root, so the package is found without installing it.
#
# If lualatex is not on PATH but a container image is (see ../latex-image),
# set LUALATEX to a wrapper, e.g.
#
#     make examples LUALATEX='container machine run -n ubuntu-latex -w $(PWD) lualatex'
#
# Note that `container machine run` splits its command string on spaces, so a
# wrapper script is usually easier than an inline command.

LUALATEX ?= lualatex
LATEXFLAGS ?= --interaction=nonstopmode --halt-on-error
PDFTOPPM ?= pdftoppm
PDFFONTS ?= pdffonts
DPI ?= 120

export TEXINPUTS := .:$(TEXINPUTS)

EXAMPLES := $(basename $(wildcard examples/*.tex))
GUIDE := docs/energese_user_guide
ARTICLE := docs/article

# Pairs whose JSON and TeX front ends must render identically.
PARITY := simple_system source-store aggregated-economy

.PHONY: all examples docs test parity render regression regression-accept \
        conformance sheet compare overlay fonts fidelity article check clean

all: examples docs

examples: $(addsuffix .pdf,$(EXAMPLES))

docs: $(GUIDE).pdf

# The paper's figures come from the fidelity harness, so build those first.
article: compare sheet
	@$(MAKE) $(ARTICLE).pdf LUALATEX='$(LUALATEX)'

# A .tex that calls \renderEnergese depends on the JSON it renders, which make
# cannot see. Depending on every model file is coarse but correct; without it a
# JSON edit leaves a stale PDF and `make parity` compares the wrong thing.
MODELS := $(wildcard examples/*.json)

# Two passes: \ref and \cite need the .aux from the first to resolve.
%.pdf: %.tex energese.sty energese-core.lua energese-shapes.tex $(MODELS)
	$(LUALATEX) $(LATEXFLAGS) -output-directory=$(dir $@) $< </dev/null >/dev/null
	$(LUALATEX) $(LATEXFLAGS) -output-directory=$(dir $@) $< </dev/null >/dev/null
	@echo "built $@"

test:
	@bash tests/run_tests.sh all

# The two front ends share one layout engine, so equivalent models must
# rasterise identically. Drift here means they have come apart.
parity: examples
	@status=0; \
	for pair in $(PARITY); do \
	    $(PDFTOPPM) -png -r $(DPI) -singlefile examples/$$pair.pdf /tmp/es-json; \
	    $(PDFTOPPM) -png -r $(DPI) -singlefile examples/$$pair-native.pdf /tmp/es-native; \
	    if cmp -s /tmp/es-json.png /tmp/es-native.png; then \
	        echo "PASS: $$pair front ends agree"; \
	    else \
	        echo "FAIL: $$pair renders differently from JSON vs TeX"; status=1; \
	    fi; \
	done; \
	exit $$status

# --- Fidelity harness (see AGENTS.md section 2) -------------------------------
# Tier 1: pixel-exact against our own approved goldens.
# Tier 2: geometric invariants measured from Odum's published symbols.

FIDELITY := python3 tests/fidelity/fidelity.py \
              --lualatex '$(LUALATEX)' --pdftoppm '$(PDFTOPPM)' \
              --pdffonts '$(PDFFONTS)'

render:
	@$(FIDELITY) render

regression: render
	@$(FIDELITY) regression

# Only after reviewing tests/fidelity/diff/. Commit goldens with the code change.
regression-accept:
	@$(FIDELITY) accept

conformance: render
	@$(FIDELITY) conformance

sheet: render
	@$(FIDELITY) sheet

# Re-derive the reference targets in invariants.json from the published sheet.
measure-reference:
	@python3 tests/fidelity/measure_reference.py

# Goldens are only comparable if the same fonts were embedded.
fonts: render
	@$(FIDELITY) fonts

fidelity: fonts regression conformance

check: test parity fidelity docs

clean:
	rm -f examples/*.pdf examples/*.aux examples/*.log examples/*.fls \
	      examples/*.fdb_latexmk examples/*.synctex.gz \
	      docs/*.aux docs/*.log docs/*.out docs/*.toc docs/*.bbl docs/*.blg \
	      tests/*/*.pdf tests/*/*.aux tests/*/*.log
