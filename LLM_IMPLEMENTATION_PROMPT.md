# LLM Implementation Prompt for Energese Package

## Context

You are an expert LaTeX and Lua developer tasked with implementing the `energese` package - a LuaLaTeX package that automatically generates Howard T. Odum's Energy Systems Language (ESL) diagrams from JSON data.

## Your Mission

Implement a complete, production-ready LaTeX package following **Test-Driven Development (TDD)** that can precisely reproduce Howard T. Odum's diagram style from JSON input.

## Key Documents

**CRITICAL**: Read these files thoroughly before starting:
1. `REQUIREMENTS.md` - Complete technical specification
2. `AGENTS.md` - Detailed TDD implementation guide with all test cases
3. `reference-images/*.png` - 7 reference diagrams you must be able to reproduce

## Success Criteria

Your implementation is complete when:
- ✅ All 10 phases of tests pass (Phases 0-9 from AGENTS.md)
- ✅ Visual regression tests pass: **All 7 reference images reproduced with RMSE < 0.05**
- ✅ JSON files created for all reference images in `examples/`
- ✅ Generated PNGs visually match reference images
- ✅ Documentation PDFs generated in `docs/generated/`
- ✅ Package can be used via `\usepackage{energese}` in any LaTeX document

## Implementation Approach: Strict TDD

### Phase-by-Phase Development

**DO NOT skip phases or write code before tests exist.**

Follow this workflow for EACH phase:

```
1. READ the phase requirements in AGENTS.md
2. CREATE the test files specified
3. RUN tests (they should FAIL initially - this is correct!)
4. IMPLEMENT the minimum code to make tests pass
5. VERIFY all tests pass
6. COMMIT before moving to next phase
```

### Phase Overview

**Phase 0**: Test Infrastructure Setup
- Create `tests/run_tests.sh`
- Set up test harness before ANY implementation

**Phase 1**: JSON Parsing and Validation
- Implement `energese.parse_json()` and schema validation
- Handle errors gracefully with clear messages

**Phase 2**: Transformity Column Calculation (X-axis)
- Implement log-scale transformity layout
- Handle duplicate Tr values correctly

**Phase 3**: Vertical Positioning Algorithm (Y-axis)
- Implement "central spine" layout method
- Find longest path for main chain
- Distribute parallel nodes symmetrically

**Phase 4**: PGF Shape Definitions
- Define all 6 Odum symbol types (source, producer, consumer, storage, interaction, transaction)
- Each shape needs custom anchors: `energy_in`, `energy_out`, `feedback_in`, `feedback_out`, `heat_sink`

**Phase 5**: Edge Routing
- Implement different edge types (energy, money_feedback, information, material)
- Feedback loops must route OVERHEAD with proper arcs

**Phase 6**: Heat Sink Generation
- Automatic heat sink lines for all nodes
- Environmental floor line at bottom

**Phase 7**: Complete Integration
- End-to-end rendering from JSON → PDF
- Test with provided fixture files

**Phase 8**: Inline JSON Environment
- Create `\begin{energeseData}...\end{energeseData}` environment
- Capture multi-line JSON within LaTeX documents

**Phase 9**: Error Handling
- Clear, helpful error messages for all failure cases
- No cryptic TeX errors exposed to users

**Phase 10**: Visual Regression Testing
- **THIS IS CRITICAL**: Create JSON files for all 7 reference images
- Implement `tests/visual-regression/test_all_references.sh`
- Iterate until RMSE < 0.05 for each reference image

## Visual Regression Testing Workflow

For each reference image in `reference-images/`:

1. **Visual Analysis**
   - Open the PNG in an image viewer
   - Identify all nodes: types, positions, labels
   - Identify all edges: sources, targets, types, routing
   - Estimate transformity values that preserve left-to-right ordering

2. **Create JSON**
   - File location: `examples/{reference_name}.json`
   - Use exact naming: `aggregated-economy.png` → `aggregated-economy.json`
   - Include metadata noting analysis assumptions

3. **Generate & Compare**
   ```bash
   cd tests/visual-regression
   ./test_all_references.sh
   ```
   
4. **Iterate**
   - Review RMSE value and diff image
   - Adjust JSON parameters (positions, magnitudes, routing options)
   - Adjust rendering code if systematic issues found
   - Repeat until RMSE < 0.05

5. **Document**
   - Generate PDF: `lualatex examples/{name}.tex`
   - Save to `docs/generated/{name}.pdf`
   - Add notes to `tests/visual-regression/README.md`

## Reference Images to Reproduce

**Priority Order** (implement in this sequence):

1. **aggregated-economy.png** - Already has JSON, validate it works
2. **source-store.png** - Simplest, good starting point for new shapes
3. **store.png** - Tests storage symbol variations
4. **strong-source.png** - Tests magnitude scaling
5. **crop-harvest.png** - Tests agricultural system with storage
6. **pyramids-as-organisers.png** - Tests hierarchical layouts
7. **modern-civilisation.png** - Most complex, final validation

## Code Structure Requirements

### Package Files

**energese.sty** (main package):
```latex
\NeedsTeXFormat{LaTeX2e}
\ProvidesPackage{energese}[2026/01/28 Energy Systems Language Diagrams]
\RequirePackage{tikz}
\RequirePackage{luacode}

% Load Lua module
\directlua{dofile("energese-core.lua")}

% Load shape definitions
\input{energese-shapes.tex}

% Main rendering command
\newcommand{\renderEnergese}[1]{%
  \directlua{energese.render_from_file("#1")}%
}

% Inline environment
\newenvironment{energeseData}{%
  % Implementation here
}{}
```

**energese-core.lua** (Lua algorithms):
```lua
energese = energese or {}

-- JSON parsing (use dkjson.lua which is already in repo)
local json = require("dkjson")

function energese.parse_json(json_string)
  -- Implementation
end

function energese.validate_schema(data)
  -- Implementation
end

function energese.calculate_transformity_columns(nodes)
  -- Implementation
end

function energese.calculate_vertical_positions(nodes, edges, tr_map, row_spacing)
  -- Implementation
end

function energese.render_from_file(filepath)
  -- Main orchestration function
  -- Calls all algorithms and generates TikZ code
end
```

**energese-shapes.tex** (PGF shapes):
```latex
\pgfdeclareshape{energese source}{
  % Circle with energy_out anchor
}

\pgfdeclareshape{energese producer}{
  % Bullet/lung shape
}

% ... define all 6 shapes
```

## Critical Implementation Notes

### Transformity Layout
- **LEFT to RIGHT** = LOW to HIGH transformity
- Use logarithmic column mapping: {1→col1, 100→col2, 10000→col3}
- Nodes with identical Tr values share same X-column
- Column spacing default: 3.0 cm

### Vertical Positioning
- Find **longest path** through the graph = main energy chain
- Main chain nodes at y=0 (centerline)
- Other nodes distributed symmetrically: +1.5, -1.5, +3.0, -3.0, etc.
- Respect layer hints: "control" → y>0, "decomposition" → y<0

### Edge Routing
- **Energy flows**: Straight lines, solid, medium weight
- **Money feedback**: Dashed lines, ARC OVERHEAD (important!)
  - Calculate arc peak: max_y + 1.5×row_spacing
  - Must clear all intermediate nodes
- **Information**: Thin solid lines
- **Material**: Medium solid lines

### Shape Anchors
Each shape MUST define:
- `center`, `north`, `south`, `east`, `west`
- `energy_in` (left side)
- `energy_out` (right side)
- `heat_sink` (bottom center)
- `feedback_in`, `feedback_out` (top)

### Heat Sinks
- Find minimum Y-coordinate of all nodes
- Environmental floor at y_min - 1.5
- Vertical dashed gray lines from each node's `heat_sink` anchor to floor
- Horizontal floor line across entire diagram

## Testing Strategy

### Unit Tests
Run after each function implementation:
```bash
./tests/run_tests.sh 1  # JSON parser
./tests/run_tests.sh 2  # Transformity columns
./tests/run_tests.sh 3  # Vertical positioning
```

### Integration Tests
Run after Phase 7:
```bash
./tests/run_tests.sh all
```

### Visual Regression
Run continuously during Phase 10:
```bash
cd tests/visual-regression
./test_all_references.sh
```

## Debugging Tips

**Test fails with cryptic TeX error?**
- Check LaTeX syntax in generated TikZ code
- Add debug prints: `tex.print("DEBUG: " .. variable)`
- Run with `lualatex --interaction=errorstopmode` to see full error

**JSON parsing fails?**
- Validate JSON syntax: `python -m json.tool file.json`
- Check for escaped backslashes in labels

**Nodes overlap?**
- Increase `column_spacing` or `row_spacing` in metadata
- Check Y-coordinate calculation for that column

**Edges cross incorrectly?**
- Verify feedback edges use overhead routing
- Check anchor points are calculated correctly

**RMSE too high?**
- Compare resolution: ensure PDF→PNG conversion uses same DPI as reference
- Check symbol sizes match reference (adjust `magnitude` parameter)
- Verify edge line weights
- Check font sizes and positioning

## Deliverables Checklist

Before considering the task complete:

- [ ] `energese.sty` - Main package file
- [ ] `energese-core.lua` - All Lua algorithms implemented
- [ ] `energese-shapes.tex` - All 6 PGF shapes defined
- [ ] `tests/run_tests.sh` - Master test runner
- [ ] All Phase 0-9 tests passing
- [ ] `tests/visual-regression/test_all_references.sh` - Visual regression script
- [ ] `tests/visual-regression/README.md` - Workflow documentation
- [ ] JSON files for all 7 reference images in `examples/`
- [ ] All 7 visual regression tests passing (RMSE < 0.05)
- [ ] `docs/generated/*.pdf` - Generated documentation for each example
- [ ] `docs/energese_user_guide.tex` - User documentation
- [ ] Example gallery (5+ examples beyond reference images)

## Final Validation

Run this complete test suite:
```bash
# Unit and integration tests
./tests/run_tests.sh all

# Visual regression
cd tests/visual-regression
./test_all_references.sh

# Manual check
cd examples
lualatex aggregated-economy.tex
# Visually inspect output PDF
```

Expected output:
```
=========================================
ENERGESE PACKAGE TEST SUMMARY
=========================================
Phase 0: ✓ PASS
Phase 1: ✓ PASS (5/5 tests)
Phase 2: ✓ PASS (5/5 tests)
Phase 3: ✓ PASS (5/5 tests)
Phase 4: ✓ PASS (6/6 shapes)
Phase 5: ✓ PASS (5/5 edge types)
Phase 6: ✓ PASS (heat sinks)
Phase 7: ✓ PASS (4/4 integrations)
Phase 8: ✓ PASS (inline JSON)
Phase 9: ✓ PASS (error handling)

=========================================
VISUAL REGRESSION TEST SUMMARY  
=========================================
Total tests: 7
Passed: 7
Failed: 0
✓ All visual regression tests passed!
```

## Your Response Format

As you work through implementation, provide updates in this format:

```
## Phase X: [Phase Name]

### Status: [In Progress / Complete]

### Tests Created:
- [List test files]

### Implementation:
- [List what you implemented]

### Test Results:
[Paste test output]

### Issues Encountered:
- [Any problems and how you solved them]

### Next Steps:
- [What you'll work on next]
```

## Start Here

**First action**: Read `AGENTS.md` completely, then begin Phase 0 by creating the test harness. Do not write any implementation code until tests exist.

**Remember**: TDD means **Test First, Always**. If you find yourself writing implementation before a failing test exists, stop and write the test first.

Good luck! You've got comprehensive documentation and clear success criteria. Follow the phases methodically and you'll build a robust, well-tested package.
