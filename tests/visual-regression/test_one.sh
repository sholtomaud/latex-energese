#!/bin/bash
set -e

# SCRIPT_DIR is where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( dirname "$( dirname "$SCRIPT_DIR" )" )"
COMPARE_SCRIPT="$SCRIPT_DIR/compare_images.py"

REF_NAME=$1
if [ -z "$REF_NAME" ]; then
    echo "Usage: $0 <reference_name>"
    exit 1
fi

EXAMPLES_DIR="$REPO_ROOT/examples"
REF_DIR="$REPO_ROOT/reference-images"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

RES=300

echo "Testing $REF_NAME at $RES DPI..."

# 1. Compile LaTeX
cat > "$RESULTS_DIR/$REF_NAME.tex" <<EOF
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\renderEnergese{$EXAMPLES_DIR/$REF_NAME.json}
\end{document}
EOF

cd "$RESULTS_DIR"
export TEXINPUTS=".:$REPO_ROOT//:"
lualatex --interaction=nonstopmode "$REF_NAME.tex" > /dev/null

# 2. Convert PDF to PNG
pdftoppm -png -r "$RES" -singlefile "$REF_NAME.pdf" "$REF_NAME-generated"

# 3. Compare
python3 "$COMPARE_SCRIPT" "$REF_DIR/$REF_NAME.png" "$REF_NAME-generated.png" "$REF_NAME-diff.png"

# Success message
if [ $? -eq 0 ]; then
    echo "PASS: RMSE within threshold"
else
    echo "FAIL: RMSE exceeded threshold"
fi
