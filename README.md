# Energese

Energese is a LuaLaTeX/TikZ-based package for automating the creation of H.T. Odum's Energy Systems Language (ESL) diagrams. It uses a JSON-driven approach to define system topologies and automatically calculates layouts based on transformity and energy flows.

## Features

- **Automated Layout:** Discrete column placement based on Transformity (Tr) and vertical alignment using the "Central Spine Method".
- **JSON Driven:** Define your system in a clean, portable JSON format.
- **Odum Shapes:** High-fidelity TikZ shapes for Sources, Producers, Consumers, Storages, Interactions, and Transactions.
- **Manual Overrides:** Support for manual `x`, `y` coordinates for precise control when needed.
- **Flexible Styling:** Customize edge types (energy, money feedback, information) and node magnitudes.
- **High Fidelity:** Support for system boundaries, heat sinks with ground symbols, and sloped labels.

## Requirements

- LuaLaTeX (TeX Live 2023 or later recommended)
- TikZ (with `positioning`, `arrows.meta`, `shapes.geometric`, `calc` libraries)
- `dkjson` Lua library (included in the repo)

## Installation

Ensure `energese.sty`, `energese-core.lua`, `energese-shapes.tex`, and `dkjson.lua` are in your LaTeX search path (usually the same directory as your main `.tex` file).

## Usage

### LaTeX Integration

```latex
\usepackage{energese}

% Render from a file
\renderEnergese{path/to/diagram.json}

% Or use an environment
\begin{energeseData}
{
  "nodes": [...],
  "edges": [...]
}
\end{energeseData}
```

### JSON Schema

A typical diagram JSON consists of `nodes`, `edges`, and optional `metadata`.

#### Nodes
- `id`: Unique identifier.
- `type`: `source`, `producer`, `consumer`, `storage`, `interaction`, `transaction`, or `text`.
- `Tr`: Transformity value (used for column placement).
- `label`: LaTeX-compatible label (use `\\\\` for backslash in JSON).
- `magnitude`: Scaling factor (default 1.0).
- `x`, `y`: (Optional) Manual coordinate overrides.

#### Edges
- `from`, `to`: Node IDs.
- `type`: `energy`, `money_feedback`, `information`, or `material`.
- `label`: Edge label.
- `options`: TikZ edge options (e.g., `bend left=20`).

#### Metadata
- `column_spacing`, `row_spacing`: Layout tuning.
- `system_boundary`: Define `x_min`, `x_max`, `y_min`, `y_max` and `label`.
- `heat_sink_label`: Label for the heat sink ground point.

## Example: Aggregated Economy

The `examples/aggregated-economy.json` file replicates a classic Odum diagram.

To generate the diagram:
```bash
python3 scripts/build_diagrams.py examples/aggregated-economy.json
```
The output will be found in `output/aggregated-economy.png`.

## Development

Run tests using the provided script:
```bash
bash tests/run_tests.sh
```
This will generate PDF and PNG outputs for all test cases in the `tests/` directory.

## License

MIT
