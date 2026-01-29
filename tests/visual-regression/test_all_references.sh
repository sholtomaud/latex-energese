#!/bin/bash
# tests/visual-regression/test_all_references.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( dirname "$( dirname "$SCRIPT_DIR" )" )"
COMPARE_SCRIPT="$SCRIPT_DIR/compare_images.py"

mkdir -p "$SCRIPT_DIR/results"

REFERENCES=(
    "aggregated-economy"
    "source-store"
    "store"
    "strong-source"
    "crop-harvest"
    "pyramids-as-organisers"
    "modern-civilisation"
)

TOTAL=0
PASSED=0

# Clean up previous results
rm -f "$SCRIPT_DIR/results/*-generated.png" "$SCRIPT_DIR/results/*-diff.png"

for ref in "${REFERENCES[@]}"; do
    echo ""
    echo "=========================================="
    echo "Testing: $ref"
    echo "=========================================="

    JSON_FILE="$REPO_ROOT/examples/$ref.json"
    REF_IMAGE="$REPO_ROOT/reference-images/$ref.png"

    if [ ! -f "$JSON_FILE" ]; then
        echo "MISSING: $JSON_FILE (Skipping)"
        continue
    fi

    TOTAL=$((TOTAL+1))

    # Generate LaTeX wrapper
    TEX_FILE="$SCRIPT_DIR/results/$ref.tex"
    cat > "$TEX_FILE" <<EOF
\documentclass{standalone}
\usepackage{energese}
\begin{document}
\renderEnergese{$JSON_FILE}
\end{document}
EOF

    # Compile
    cd "$SCRIPT_DIR/results"
    export TEXINPUTS=".:$REPO_ROOT//:"
    lualatex --interaction=nonstopmode "$ref.tex" > /dev/null 2>&1

    if [ ! -f "$ref.pdf" ]; then
        echo "FAIL: Compilation failed for $ref"
        # Try to show error from log
        grep -A 5 "!" "$ref.log" | head -n 10
        continue
    fi

    # Convert to PNG
    # Use -singlefile to avoid -1.png suffix if only one page
    pdftoppm -png -r 300 -singlefile "$ref.pdf" "$ref-generated"

    # Compare
    python3 "$COMPARE_SCRIPT" "$REF_IMAGE" "$ref-generated.png" "$ref-diff.png"

    if [ $? -eq 0 ]; then
        PASSED=$((PASSED+1))
        echo "PASS: $ref"
    else
        echo "FAIL: $ref exceeded RMSE threshold"
    fi
done

echo ""
echo "=========================================="
echo "SUMMARY: $PASSED / $TOTAL passed"
echo "=========================================="

if [ "$PASSED" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    exit 0
else
    exit 1
fi
