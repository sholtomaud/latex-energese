# Energese LaTeX Package: Complete Requirements Specification

## 1. Executive Summary

The `energese` package automates the rendering of H.T. Odum's Energy Systems Language (ESL) diagrams using a data-driven approach via LuaLaTeX and TikZ. The package implements Odum's implicit layout rules algorithmically, enabling users to specify complex ecological and industrial systems via JSON data structures rather than manual TikZ coding.

**The package aims to precisely reproduce the visual style and layout of Howard T. Odum's original diagrams, validated through visual regression testing against reference images.** This ensures that generated diagrams maintain the aesthetic and scientific accuracy of Odum's original work.

## 2. Theoretical Foundation

### 2.1 Horizontal Axis (X): Energy Quality (Transformity)
- **Definition**: Transformity is the energy of one type required to make one unit of energy of another type
- **Units**: solar emjoules per joule (sej/J)
- **Layout Rule**: X-position is strictly determined by log-scale transformity ranking
- **Thermodynamic Basis**: Represents the Second Law of Thermodynamics and energy hierarchy

### 2.2 Vertical Axis (Y): System Structure and Flow Divergence
The vertical axis represents several overlapping concepts:
- **Parallelism**: Multiple components at same trophic level
- **Functional Role**: Main throughput (y≈0) vs. control/feedback (y>0) vs. decomposition (y<0)
- **Spatial Organization**: Visual clarity and minimization of line crossings

**Key Insight from Discussion**: The Y-axis is NOT strictly storage capacity, but rather:
1. Functional layer (control/main/decomposition)
2. Degree of branching/parallelism
3. Aesthetic optimization for clarity

### 2.3 The Heat Sink Principle
- All energy eventually degrades to heat (entropy)
- Visual representation: All components have downward arrows to a common "environmental floor"
- The heat sink line is always the lowest Y-coordinate in the diagram

## 3. Functional Requirements

### 3.1 Data Input and Parsing

#### 3.1.1 External JSON File Input
```latex
\renderEnergese{path/to/file.json}
```
- Shall accept relative or absolute file paths
- Shall provide clear error messages if file not found or JSON invalid

#### 3.1.2 Inline JSON Environment
```latex
\begin{energeseData}
{
  "metadata": {...},
  "nodes": [...],
  "edges": [...]
}
\end{energeseData}
```
- Shall capture multi-line JSON within LaTeX document
- Shall parse immediately upon environment closure

### 3.2 JSON Schema Specification

#### 3.2.1 Metadata Object
```json
{
  "metadata": {
    "name": "System Name (optional)",
    "show_grid": true|false,
    "show_axis": true|false,
    "show_heat_sink": true|false,
    "column_spacing": 3.0,
    "row_spacing": 1.5,
    "grid_type": "rectangular"|"hexagonal"
  }
}
```

#### 3.2.2 Node Object
```json
{
  "id": "unique_identifier",
  "label": "Display Name",
  "type": "source"|"producer"|"consumer"|"storage"|"interaction"|"transaction",
  "Tr": 1.0,
  "layer_hint": "control"|"main"|"decomposition" (optional),
  "y_gravity": 0.0 (optional, manual vertical nudge),
  "magnitude": 1.0 (optional, affects symbol size)
}
```

**Node Types and Symbols**:
- `source`: Circle (energy inputs: sun, wind, tide, rain)
- `producer`: Bullet/Lung shape (plants, photosynthesizers)
- `consumer`: Hexagon (animals, machines, humans)
- `storage`: Tank symbol (biomass, inventories, populations)
- `interaction`: Pointed block (limiting processes, valves)
- `transaction`: Diamond (economic exchanges, markets)

#### 3.2.3 Edge Object
```json
{
  "from": "node_id",
  "to": "node_id",
  "type": "energy"|"money_feedback"|"information"|"material",
  "volume": 1.0 (optional, affects line thickness)
}
```

**Edge Types**:
- `energy`: Solid line with arrow (forward energy flow)
- `money_feedback`: Dashed line, routed overhead (economic feedback)
- `information`: Thin line with specialized arrow (control signals)
- `material`: Medium weight line (matter flows)

### 3.3 Layout Engine: The "Odum Algorithm"

#### 3.3.1 Phase 1: X-Axis (Transformity-Based Ranking)

**Algorithm**:
```
1. Extract all unique Tr values from nodes
2. Sort Tr values in ascending order
3. Apply logarithmic compression:
   - If Tr values span multiple orders of magnitude (e.g., 1, 100, 10000)
   - Map to integer columns: {1→col1, 100→col2, 10000→col3}
   - Column X-coordinate: col_index × column_spacing

4. Handle duplicate Tr values:
   - All nodes with identical Tr share the same X-column
   - Vertical distribution handled in Y-pass
```

**Column Compression Logic**:
- Creates discrete integer columns (1, 2, 3, ...) from sorted unique Tr values
- Eliminates "empty space" between widely disparate magnitudes
- Preserves strict thermodynamic ordering

#### 3.3.2 Phase 2: Y-Axis (Structural Layout)

**Primary Algorithm - "Central Spine Method"**:
```
1. Identify the "main energy chain":
   - Perform graph traversal from highest-Tr source
   - Find longest path to lowest-Tr consumer
   - This is the "primary throughput path"

2. Assign main chain nodes to y=0 (centerline)

3. For each X-column:
   a. Count nodes in that column
   b. Identify which are on main chain (y=0)
   c. For remaining nodes, apply symmetric stacking:
      - First alternate: y = +row_spacing
      - Second alternate: y = -row_spacing
      - Third alternate: y = +2×row_spacing
      - Fourth alternate: y = -2×row_spacing
      - Continue pattern...

4. Apply functional layer hints:
   - "control" nodes: bias toward y > 0
   - "decomposition" nodes: bias toward y < 0
   - "main" nodes: keep near y = 0

5. Apply y_gravity parameter (if specified in JSON):
   - Final Y = calculated_Y + y_gravity
```

**Alternative Algorithm - "Branching Degree Method"**:
```
1. Calculate "betweenness centrality" for each node:
   - Nodes with high betweenness → y ≈ 0
   - Nodes with low betweenness → y offset

2. For nodes at same Tr with common parent:
   - If Parent→[A, B, C] (three children)
   - Distribute: A at y=+d, B at y=0, C at y=-d

3. For feedback vs. mainline:
   - Money/transaction nodes → upper half (y > 0)
   - Decomposition/waste → lower half (y < 0)
```

#### 3.3.3 Phase 3: Heat Sink Calculation
```
1. Calculate y_min = minimum Y coordinate of all nodes - margin
2. Draw horizontal "environmental floor" line at y_min
3. For each node:
   - Calculate heat_sink anchor position (bottom of symbol)
   - Draw vertical line from heat_sink to y_min
   - Style: thin, dashed, gray
```

### 3.4 Geometric Rendering (TikZ/PGF)

#### 3.4.1 Custom PGF Shape Library

Each shape SHALL define these anchors:
- **Cardinal**: north, south, east, west, center
- **Energy**: energy_in (left side), energy_out (right side)
- **Feedback**: feedback_in (top-left), feedback_out (top-right)
- **Heat**: heat_sink (bottom center)

**Shape Specifications**:

**Source (Circle)**:
- Radius: 0.4 units (scalable by magnitude parameter)
- Single energy_out anchor on east side

**Producer (Bullet/Lung)**:
- Width: 1.0 unit, Height: 0.8 units
- Left side: rounded (energy input)
- Right side: pointed (concentrated energy output)
- Multiple energy_in anchors on left curve for parallel inputs

**Consumer (Hexagon)**:
- Regular hexagon, width: 1.0 unit
- Top vertices: information/control input
- Left/right vertices: energy in/out
- Bottom: heat sink

**Storage (Tank)**:
- Rectangular base with curved top
- Width: 0.8 units, Height: 1.2 units
- Inputs at top, outputs at sides/bottom

**Interaction (Pointed Block)**:
- Elongated hexagon with sharp point on right
- Represents limiting factors or valves
- Two inputs (top and bottom left), one output (right point)

**Transaction (Diamond)**:
- 45° rotated square
- Used for economic exchanges
- Typically has money_feedback connections

#### 3.4.2 Path Routing

**Forward Energy Flows** (type: "energy" or "material"):
```
- Style: solid line, medium weight
- Arrow: filled triangle at destination
- Routing: Straight line or minimal curve (max 15° bend)
- Connects from_node.energy_out to to_node.energy_in
```

**Feedback Loops** (type: "money_feedback"):
```
- Style: dashed line
- Arrow: open triangle
- Routing: Overhead arc
  - Calculate max_y = highest Y coordinate between from/to columns
  - Arc peak at max_y + 1.5×row_spacing
  - Ensures arc clears all intermediate nodes
- Connects from_node.feedback_out to to_node.feedback_in
```

**Information Flows** (type: "information"):
```
- Style: thin solid line
- Arrow: small open triangle
- Used for control signals, typically to interaction nodes
```

### 3.5 Automatic Layout Optimization

#### 3.5.1 Collision Detection and Resolution
```
For each node pair (A, B):
  If A and B have overlapping bounding boxes:
    - If same X-column: increase Y-spacing for that column
    - If adjacent X-columns: check edge paths
      - If edges cross: adjust Y-positions or reroute
```

#### 3.5.2 Edge Bundling (Advanced Feature)
```
If multiple edges connect same (X_from, X_to) column pair:
  - Bundle parallel edges into single thick path
  - Split at destination with small fan-out
  - Annotate with combined flow volume
```

### 3.6 Visual Regression Testing

#### 3.6.1 Reference Image Repository
- **Location**: `reference-images/` directory
- **Source**: Original H.T. Odum diagrams from published works
- **Format**: High-resolution PNG files
- **Purpose**: Ground truth for visual fidelity validation

#### 3.6.2 Test Workflow
1. Each reference image SHALL have a corresponding JSON data file in `examples/`
2. JSON file SHALL be named to match reference image (e.g., `aggregated-economy.json` ↔ `aggregated-economy.png`)
3. Automated tests SHALL:
   - Render JSON to PDF using `\renderEnergese{}`
   - Convert PDF to PNG at same resolution as reference
   - Perform pixel-wise or perceptual image comparison
   - Report quantitative difference metrics (RMSE, structural similarity)

#### 3.6.3 Acceptance Criteria
- Generated diagrams MUST match reference images within defined tolerance
- Default threshold: **RMSE < 0.05** (5% difference) OR pixel difference < 2%
- Critical elements (symbol shapes, arrow directions, text labels) MUST match exactly
- Minor variations in anti-aliasing or font rendering are acceptable

#### 3.6.4 Comparison Tools
- **Primary**: ImageMagick `compare -metric RMSE`
- **Alternative**: Python `scikit-image` structural similarity index (SSIM)
- **Output**: Difference images highlighting mismatches in `tests/visual-regression/diffs/`

#### 3.6.5 LLM Developer Workflow
For each reference image:
1. **Analyze Reference**: Examine the PNG to identify nodes, edges, transformity ordering, and layout
2. **Create JSON**: Design corresponding JSON data file in `examples/`
3. **Generate Output**: Compile JSON to PDF, convert to PNG
4. **Compare**: Run visual regression test, review RMSE and diff image
5. **Iterate**: Adjust JSON parameters and rendering code until RMSE < 0.05
6. **Document**: Generate PDF for `docs/generated/` and commit

#### 3.6.6 Reference Image Catalog
The repository includes the following reference diagrams:
- `aggregated-economy.png` - Multi-level economic system with feedback loops
- `crop-harvest.png` - Agricultural system with storage and seasonal flows
- `modern-civilisation.png` - Complex civilizational system with multiple layers
- `pyramids-as-organisers.png` - Hierarchical energy pyramid structure
- `source-store.png` - Basic source and storage interaction
- `store.png` - Storage symbol variations and connections
- `strong-source.png` - High-magnitude energy source with downstream effects

## 4. Non-Functional Requirements

### 4.1 Technical Requirements
- **LaTeX Engine**: Requires LuaLaTeX (not pdflatex or xelatex)
- **Dependencies**: tikz, pgf, luacode packages
- **JSON Parser**: Implement using Lua's native dkjson or lunajson library
- **Coordinate System**: TikZ canvas with units in cm

### 4.2 Performance Requirements
- Shall render diagrams with up to 50 nodes in <5 seconds compile time
- Shall handle up to 150 edges without significant slowdown
- Shall provide progress indicators for large diagrams

### 4.3 Error Handling
- Invalid JSON: Clear error message with line number
- Undefined node reference in edge: List all invalid references
- Circular feedback without proper routing: Warning message
- Overlapping nodes: Suggest increasing spacing parameters

### 4.4 Visual Quality
- All output shall be publication-ready vector graphics
- Default colors: black for energy, blue for money, gray for heat
- Line weights: 1pt for main flows, 0.5pt for feedback, 0.25pt for heat
- Consistent symbol proportions matching Odum's textbook diagrams
- **Generated diagrams SHALL match reference images with quantitative fidelity metrics (RMSE < 0.05)**
- **All reference images in `reference-images/` SHALL have passing visual regression tests**

## 5. Implementation Architecture

### 5.1 Package Structure
```
energese.sty          # Main package file
  ├── energese-core.lua      # JSON parsing and layout algorithm
  ├── energese-shapes.tex    # PGF shape definitions
  ├── energese-styles.tex    # TikZ style definitions
  └── energese-examples/     # Sample JSON files
```

### 5.2 Lua Processing Pipeline
```lua
-- High-level pseudocode
function render_energese(json_input)
  -- Step 1: Parse and validate
  data = parse_json(json_input)
  validate_schema(data)
  
  -- Step 2: X-axis layout
  tr_map = calculate_transformity_columns(data.nodes)
  
  -- Step 3: Y-axis layout
  y_coords = calculate_vertical_positions(data.nodes, data.edges, tr_map)
  
  -- Step 4: Route edges
  paths = calculate_edge_paths(data.edges, tr_map, y_coords)
  
  -- Step 5: Generate TikZ code
  tex.print("\\begin{tikzpicture}")
  emit_grid(data.metadata)
  emit_nodes(data.nodes, tr_map, y_coords)
  emit_edges(paths)
  emit_heat_sinks(data.nodes, y_coords)
  tex.print("\\end{tikzpicture}")
end
```

### 5.3 Key Algorithms

#### Transform Calculation (X-Axis)
```lua
function calculate_transformity_columns(nodes)
  local tr_values = {}
  for _, node in ipairs(nodes) do
    table.insert(tr_values, node.Tr)
  end
  
  -- Get unique values and sort
  tr_values = unique_sorted(tr_values)
  
  -- Create mapping: Tr → Column
  local tr_map = {}
  for i, tr in ipairs(tr_values) do
    tr_map[tr] = i
  end
  
  return tr_map
end
```

#### Vertical Positioning (Y-Axis)
```lua
function calculate_vertical_positions(nodes, edges, tr_map)
  -- Step 1: Build adjacency graph
  local graph = build_directed_graph(edges)
  
  -- Step 2: Find main chain (longest path)
  local main_chain = find_longest_path(graph)
  
  -- Step 3: Initialize Y coordinates
  local y_coords = {}
  for _, node in ipairs(main_chain) do
    y_coords[node.id] = 0  -- Main chain at centerline
  end
  
  -- Step 4: Distribute remaining nodes
  for col = 1, #tr_map do
    local nodes_in_col = get_nodes_by_column(nodes, col, tr_map)
    local non_main = filter_out(nodes_in_col, main_chain)
    
    -- Symmetric stacking
    for i, node in ipairs(non_main) do
      local offset = math.ceil(i / 2)
      local sign = (i % 2 == 1) and 1 or -1
      y_coords[node.id] = sign * offset * row_spacing
    end
  end
  
  -- Step 5: Apply layer hints and gravity
  apply_layer_biases(y_coords, nodes)
  
  return y_coords
end
```

## 6. User Interface and Package Commands

### 6.1 Main Commands
```latex
% Render from external file
\renderEnergese[options]{filepath.json}

% Options (key-value):
% - scale=<float>: Scale entire diagram
% - debug=true: Show grid and node labels
% - colorscheme=<name>: Apply color theme
```

### 6.2 Configuration Commands
```latex
% Set global defaults
\energeseSetup{
  column spacing = 3cm,
  row spacing = 1.5cm,
  grid type = rectangular,
  auto heat sink = true
}
```

### 6.3 Debug and Inspection
```latex
% Show transformity values above each column
\energeseShowTransformities

% Export calculated coordinates to CSV
\energeseExportCoordinates{output.csv}
```

## 7. Test Cases and Validation

### 7.1 Minimal Test Case
```json
{
  "nodes": [
    {"id": "S1", "type": "source", "Tr": 1, "label": "Sun"},
    {"id": "P1", "type": "producer", "Tr": 100, "label": "Grass"},
    {"id": "C1", "type": "consumer", "Tr": 2000, "label": "Cow"}
  ],
  "edges": [
    {"from": "S1", "to": "P1", "type": "energy"},
    {"from": "P1", "to": "C1", "type": "energy"}
  ]
}
```
**Expected Output**: Three symbols in ascending X-order, connected by solid arrows, with heat sink lines below.

### 7.2 Branching Test Case
```json
{
  "nodes": [
    {"id": "S1", "type": "source", "Tr": 1, "label": "Rain"},
    {"id": "P1", "type": "producer", "Tr": 100, "label": "Trees"},
    {"id": "P2", "type": "producer", "Tr": 100, "label": "Grass"},
    {"id": "C1", "type": "consumer", "Tr": 2000, "label": "Deer"}
  ],
  "edges": [
    {"from": "S1", "to": "P1", "type": "energy"},
    {"from": "S1", "to": "P2", "type": "energy"},
    {"from": "P1", "to": "C1", "type": "energy"},
    {"from": "P2", "to": "C1", "type": "energy"}
  ]
}
```
**Expected Output**: P1 and P2 should be vertically offset (same column), C1 should receive two input arrows.

### 7.3 Feedback Loop Test Case
```json
{
  "nodes": [
    {"id": "P1", "type": "producer", "Tr": 100, "label": "Factory"},
    {"id": "C1", "type": "consumer", "Tr": 5000, "label": "Market"},
    {"id": "T1", "type": "transaction", "Tr": 10000, "label": "Bank"}
  ],
  "edges": [
    {"from": "P1", "to": "C1", "type": "energy"},
    {"from": "C1", "to": "T1", "type": "energy"},
    {"from": "T1", "to": "P1", "type": "money_feedback"}
  ]
}
```
**Expected Output**: Solid arrow from P1→C1→T1, dashed arc from T1 back to P1 that routes overhead.

### 7.4 Visual Regression Test Cases

For each reference image, the following SHALL be validated:

#### 7.4.1 aggregated-economy.png
- **JSON**: `examples/aggregated-economy.json`
- **Tests**: Node positioning, feedback loops, system boundary rendering
- **Critical features**: Multi-level transformity layout, curved feedback arrows, heat sink labeling
- **Key validation points**:
  - 6 distinct transformity levels correctly arranged
  - Money feedback loops routed overhead with proper arcs
  - System boundary box rendered with label
  - Heat sink numerical annotations displayed

#### 7.4.2 crop-harvest.png
- **JSON**: `examples/crop-harvest.json` (to be created)
- **Tests**: Agricultural system with storage and seasonal flows
- **Critical features**: Storage tank symbols, multiple source inputs
- **Key validation points**:
  - Storage symbol anchor points correctly positioned
  - Multiple sources (sun, rain) connect to same producer
  - Seasonal/cyclical flows if present

#### 7.4.3 modern-civilisation.png
- **JSON**: `examples/modern-civilisation.json` (to be created)
- **Tests**: Complex multi-layer system with economic feedback
- **Critical features**: Layer separation (control, main, decomposition)
- **Key validation points**:
  - Control layer nodes positioned above main energy flow
  - Decomposition layer nodes positioned below
  - Multiple crossing edges routed without overlap
  - Large-scale system maintains readability

#### 7.4.4 pyramids-as-organisers.png
- **JSON**: `examples/pyramids-as-organisers.json` (to be created)
- **Tests**: Hierarchical energy pyramid structure
- **Critical features**: Pyramidal layout, energy quality gradients
- **Key validation points**:
  - Hierarchical node arrangement (pyramid shape)
  - Transformity increases vertically and left-to-right
  - Symmetrical branching patterns
  - Energy convergence visualization

#### 7.4.5 source-store.png
- **JSON**: `examples/source-store.json` (to be created)
- **Tests**: Basic source and storage interaction
- **Critical features**: Minimal system, interaction symbols
- **Key validation points**:
  - Source circle symbol rendering
  - Storage tank symbol rendering
  - Interaction (valve) symbol if present
  - Simple linear flow layout

#### 7.4.6 store.png
- **JSON**: `examples/store.json` (to be created)
- **Tests**: Storage symbol variations and connections
- **Critical features**: Storage tank at different states/sizes
- **Key validation points**:
  - Storage symbol anchor points (energy_in, energy_out, heat_sink)
  - Input/output edge connections to correct anchors
  - Symbol proportions match reference
  - Multiple storage configurations if shown

#### 7.4.7 strong-source.png
- **JSON**: `examples/strong-source.json` (to be created)
- **Tests**: High-magnitude source symbol scaling
- **Critical features**: Magnitude parameter effects
- **Key validation points**:
  - Source symbol scales correctly with magnitude parameter
  - Line thickness increases for high-volume flows
  - Downstream effects of concentrated energy
  - Symbol remains recognizable at larger sizes

## 8. Future Enhancements (Out of Scope for V1)

### 8.1 Interactive Features
- Clickable nodes with popup information
- Animation of energy flows
- Integration with Beamer for presentations

### 8.2 Advanced Layout Options
- Force-directed refinement after initial placement
- Manual node positioning override
- Constraint-based layout (user specifies "A must be above B")

### 8.3 Data Analysis Integration
- Import from Excel/CSV with automatic type inference
- Calculate transformity values from emergy tables
- Validate thermodynamic consistency (energy balance checks)

### 8.4 Multi-Page Diagrams
- Automatic splitting of large systems
- Hierarchical zoom levels (overview → detail)
- Cross-reference connectors between pages

## 9. Glossary

- **Transformity**: Solar emjoules per joule; measure of energy quality
- **Emergy**: Available energy of one kind previously used directly and indirectly to make a product
- **Energy Systems Language (ESL)**: H.T. Odum's graphical notation for systems ecology
- **Heat Sink**: The ultimate destination of all energy (entropy)
- **Feedback Loop**: A flow that returns to earlier stages in the system
- **Trophic Level**: Position in the food chain/energy hierarchy

## 10. References

- Odum, H.T. (1996). Environmental Accounting: Emergy and Environmental Decision Making. Wiley.
- Odum, H.T. (1983). Systems Ecology: An Introduction. Wiley-Interscience.
- Brown, M.T., & Ulgiati, S. (2004). Energy quality, emergy, and transformity. The Science of the Total Environment, 326(1-3), 1-10.

---

## Appendix A: Complete JSON Schema (Formal)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["nodes", "edges"],
  "properties": {
    "metadata": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "show_grid": {"type": "boolean", "default": false},
        "show_axis": {"type": "boolean", "default": true},
        "show_heat_sink": {"type": "boolean", "default": true},
        "column_spacing": {"type": "number", "default": 3.0},
        "row_spacing": {"type": "number", "default": 1.5},
        "grid_type": {"type": "string", "enum": ["rectangular", "hexagonal"], "default": "rectangular"}
      }
    },
    "nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "type", "Tr", "label"],
        "properties": {
          "id": {"type": "string"},
          "label": {"type": "string"},
          "type": {"type": "string", "enum": ["source", "producer", "consumer", "storage", "interaction", "transaction"]},
          "Tr": {"type": "number", "minimum": 0},
          "layer_hint": {"type": "string", "enum": ["control", "main", "decomposition"]},
          "y_gravity": {"type": "number", "default": 0},
          "magnitude": {"type": "number", "default": 1.0, "minimum": 0}
        }
      }
    },
    "edges": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["from", "to", "type"],
        "properties": {
          "from": {"type": "string"},
          "to": {"type": "string"},
          "type": {"type": "string", "enum": ["energy", "money_feedback", "information", "material"]},
          "volume": {"type": "number", "default": 1.0, "minimum": 0}
        }
      }
    }
  }
}
```

## Appendix B: Implementation Checklist for LLM

- [ ] Create `energese.sty` package header with LuaLaTeX requirement
- [ ] Implement JSON parser with schema validation
- [ ] Define PGF shapes for all 6 node types with custom anchors
- [ ] Implement transformity column calculation algorithm
- [ ] Implement central spine Y-axis layout algorithm
- [ ] Implement edge routing with overhead feedback detection
- [ ] Implement automatic heat sink line generation
- [ ] Create TikZ code emission functions
- [ ] Add error handling and user-friendly messages
- [ ] Write package documentation with examples
- [ ] Create test suite with all validation cases
- [ ] Optimize for performance (50+ nodes)
- [ ] **Create JSON files for all 7 reference images**
- [ ] **Implement visual regression test suite (`tests/visual-regression/test_all_references.sh`)**
- [ ] **Set up automated image comparison pipeline**
- [ ] **Generate reference documentation PDFs in `docs/generated/`**
- [ ] **Document workflow for LLM developers to add new examples**
- [ ] **Ensure all reference images pass visual regression tests (RMSE < 0.05)**

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-28  
**Status**: Ready for Implementation
