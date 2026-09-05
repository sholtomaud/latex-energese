#!/bin/bash
# tests/run_tests.sh

# Usage: ./run_tests.sh [phase_number]
# Returns: 0 if all tests pass, 1 if any fail

PHASE=${1:-all}
FAILED=0

# Overridable so the suite can run against a containerised or otherwise
# non-PATH engine; the Makefile passes its own LUALATEX through.
LUALATEX=${LUALATEX:-lualatex}

run_test_suite() {
    local suite=$1
    echo "=========================================="
    echo "Running: $suite"
    echo "=========================================="

    local dir=$(dirname "$suite")
    local base=$(basename "$suite")
    if "$LUALATEX" --interaction=nonstopmode --output-directory="$dir" "$suite.tex" > /dev/null 2>&1; then
        echo "✓ PASS: $suite"
        # Generate PNG for visual verification
        if [ -f "${suite}.pdf" ]; then
            pdftoppm -png -singlefile "${suite}.pdf" "$suite"
            echo "  Generated: ${suite}.png"
        fi
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

# Asserting, not just compiling: test_ports raises a TeX error when a port rule
# is broken, so a failure here is a failure of the rule and not of the build.
if [ "$PHASE" == "all" ] || [ "$PHASE" == "5" ]; then
    run_test_suite "tests/unit/test_ports"
fi

# Lua-level assertions about the layout engine: the path a router returns, the
# lanes the dissipation bundle nests in, where a modifier attaches, what the
# system window encloses. A picture cannot fail these; the numbers can.
if [ "$PHASE" == "all" ] || [ "$PHASE" == "6" ]; then
    run_test_suite "tests/unit/test_routing"
fi

# Reading a GSSK model: the normalisation that lets one file simulate and draw.
if [ "$PHASE" == "all" ] || [ "$PHASE" == "7" ]; then
    run_test_suite "tests/unit/test_gssk"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "8" ]; then
    run_test_suite "tests/integration/test_edge_routing"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "9" ]; then
    run_test_suite "tests/integration/test_heat_sinks"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "10" ]; then
    run_test_suite "tests/integration/test_complete_rendering"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "11" ]; then
    run_test_suite "tests/integration/test_inline_json"
fi

if [ "$PHASE" == "all" ] || [ "$PHASE" == "12" ]; then
    suite="tests/integration/test_error_messages"
    echo "=========================================="
    echo "Running: $suite (expecting errors)"
    echo "=========================================="
    "$LUALATEX" --interaction=nonstopmode --output-directory="tests/integration" "$suite.tex" > /dev/null 2>&1

    # Check for expected error patterns in log
    MISSING_ERRORS=0
    grep "Module energese Error: File not found: nonexistent_file.json" "${suite}.log" > /dev/null || { echo "✗ Missing: File not found error"; MISSING_ERRORS=1; }
    grep "Module energese Error: Invalid JSON syntax" "${suite}.log" > /dev/null || { echo "✗ Missing: Invalid JSON syntax error"; MISSING_ERRORS=1; }
    grep "Node 'A' missing required field 'Tr'" "${suite}.log" > /dev/null || { echo "✗ Missing: Missing field Tr error"; MISSING_ERRORS=1; }
    grep "Edge references undefined node 'B'" "${suite}.log" > /dev/null || { echo "✗ Missing: Undefined node error"; MISSING_ERRORS=1; }

    if [ $MISSING_ERRORS -eq 0 ]; then
        echo "✓ PASS: $suite (All expected errors caught)"
    else
        echo "✗ FAIL: $suite (Some expected errors were NOT caught)"
        FAILED=1
    fi
fi

exit $FAILED
