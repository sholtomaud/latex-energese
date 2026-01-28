#!/bin/bash
# tests/run_tests.sh

# Usage: ./run_tests.sh [phase_number]
# Returns: 0 if all tests pass, 1 if any fail

PHASE=${1:-all}
FAILED=0

run_test_suite() {
    local suite=$1
    echo "=========================================="
    echo "Running: $suite"
    echo "=========================================="

    local dir=$(dirname "$suite")
    local base=$(basename "$suite")
    if lualatex --interaction=nonstopmode --output-directory="$dir" "$suite.tex" > /dev/null 2>&1; then
        echo "✓ PASS: $suite"
    else
        echo "✗ FAIL: $suite"
        FAILED=1
        # Extract last error from log
        if [ -f "${suite}.log" ]; then
            cat "${suite}.log" | grep -A 5 "^!" | head -n 20
        fi
    fi
}

# Run appropriate test phase
if [ "$PHASE" == "all" ] || [ "$PHASE" == "1" ]; then
    run_test_suite "tests/unit/test_json_parser"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "2" ]; then
    run_test_suite "tests/unit/test_transformity_columns"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "3" ]; then
    run_test_suite "tests/unit/test_vertical_positioning"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "4" ]; then
    run_test_suite "tests/unit/test_shapes"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "5" ]; then
    run_test_suite "tests/integration/test_edge_routing"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "6" ]; then
    run_test_suite "tests/integration/test_heat_sinks"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "7" ]; then
    run_test_suite "tests/integration/test_complete_rendering"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "8" ]; then
    run_test_suite "tests/integration/test_inline_json"
fi

exit $FAILED
