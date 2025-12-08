#!/bin/bash
# Run vep-schema generator tests
#
# Usage:
#   ./run-tests.sh           # Run all tests
#   ./run-tests.sh explore   # Explore IFEX structure (for development)
#   ./run-tests.sh proto     # Test protobuf generation only
#   ./run-tests.sh idl       # Test DDS IDL generation only
#   ./run-tests.sh validate  # Validate IFEX syntax only
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure image exists
if ! docker image inspect vep-schema-tools &>/dev/null; then
    echo "Image not found. Building..."
    ./build-tool.sh
fi

# Helper to run commands in container as current user
run_in_container() {
    docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -w /workspace \
        -u "$(id -u):$(id -g)" \
        --entrypoint /bin/bash \
        vep-schema-tools \
        -c "$1"
}

# Test result tracking via temp file (persists across subcommands)
# If RESULTS_FILE is inherited from parent, use it; otherwise create new
if [ -z "$RESULTS_FILE" ] || [ ! -f "$RESULTS_FILE" ]; then
    RESULTS_FILE=$(mktemp)
    echo "0 0 0" > "$RESULTS_FILE"
    trap "rm -f $RESULTS_FILE" EXIT
fi

report_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    read P F S < "$RESULTS_FILE"
    echo "$((P+1)) $F $S" > "$RESULTS_FILE"
}

report_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    echo "  $2"
    read P F S < "$RESULTS_FILE"
    echo "$P $((F+1)) $S" > "$RESULTS_FILE"
}

report_skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    echo "  $2"
    read P F S < "$RESULTS_FILE"
    echo "$P $F $((S+1))" > "$RESULTS_FILE"
}

get_results() {
    read TESTS_PASSED TESTS_FAILED TESTS_SKIPPED < "$RESULTS_FILE"
}

# Test output goes to tests/generated/ (separate from main generated/)
TEST_OUTPUT_DIR="tests/generated"

case "${1:-all}" in
    explore)
        echo "=== Exploring IFEX structure ==="
        echo ""
        echo "--- Template directories ---"
        run_in_container "ls -la /opt/ifex/ifex/templates/ 2>/dev/null || echo 'No templates/ dir'"
        run_in_container "ls -la /opt/ifex/ifex/output_filters/templates/ 2>/dev/null || echo 'No output_filters/templates/ dir'"
        echo ""
        echo "--- Template files ---"
        run_in_container "find /opt/ifex -name '*.tpl' -type f 2>/dev/null | head -30"
        echo ""
        echo "--- Protobuf template (if exists) ---"
        run_in_container "find /opt/ifex -path '*protobuf*' -name '*.tpl' -type f 2>/dev/null | head -10"
        echo ""
        echo "--- Custom templates in workspace ---"
        run_in_container "ls -la /workspace/templates/ 2>/dev/null || echo 'No custom templates yet'"
        echo ""
        echo "--- IFEX model/AST files ---"
        run_in_container "find /opt/ifex -name '*.py' -path '*model*' -type f 2>/dev/null | head -20"
        echo ""
        echo "--- ifexgen help ---"
        run_in_container "ifexgen --help 2>&1 | head -40"
        ;;

    validate)
        echo "=== Validating IFEX files ==="
        echo ""

        # Validate test IFEX files
        for f in tests/ifex/*.ifex; do
            name=$(basename "$f" .ifex)
            if run_in_container "python3 -c \"
import yaml
import sys
with open('/workspace/$f', 'r') as file:
    data = yaml.safe_load(file)
if 'name' not in data:
    sys.exit(1)
if 'namespaces' not in data:
    sys.exit(1)
\"" 2>/dev/null; then
                report_pass "tests/ifex/$name.ifex - valid IFEX syntax"
            else
                report_fail "tests/ifex/$name.ifex" "Invalid IFEX syntax"
            fi
        done

        # Validate main IFEX files
        echo ""
        echo "--- Main IFEX files ---"
        for f in ifex/*.ifex; do
            name=$(basename "$f" .ifex)
            if run_in_container "python3 -c \"
import yaml
import sys
with open('/workspace/$f', 'r') as file:
    data = yaml.safe_load(file)
if 'name' not in data:
    sys.exit(1)
if 'namespaces' not in data:
    sys.exit(1)
\"" 2>/dev/null; then
                report_pass "ifex/$name.ifex - valid IFEX syntax"
            else
                report_fail "ifex/$name.ifex" "Invalid IFEX syntax"
            fi
        done
        ;;

    proto)
        echo "=== Testing Protobuf generation ==="
        echo ""

        # Create output directory for test artifacts
        mkdir -p "$TEST_OUTPUT_DIR/proto"

        # Check if custom template exists, otherwise use IFEX default
        TEMPLATE_DIR=""
        if [ -d "templates/protobuf" ]; then
            TEMPLATE_DIR="/workspace/templates/protobuf"
            echo "Using custom template: templates/protobuf"
        else
            # Use the correct IFEX template path
            TEMPLATE_DIR="/opt/ifex/ifex/output_filters/templates/protobuf"
            echo "Using IFEX default template: $TEMPLATE_DIR"
        fi

        if [ -z "$TEMPLATE_DIR" ]; then
            report_skip "Protobuf generation" "No protobuf template found"
            exit 0
        fi

        echo ""
        echo "--- Running protobuf generation tests ---"
        echo ""

        for f in tests/ifex/*.ifex; do
            name=$(basename "$f" .ifex)
            expected="tests/expected/proto/${name}.proto"
            output="$TEST_OUTPUT_DIR/proto/${name}.proto"

            # Generate
            if ! run_in_container "ifexgen -d '$TEMPLATE_DIR' '/workspace/$f'" > "$output" 2>&1; then
                report_fail "$name.ifex → proto" "Generation failed"
                continue
            fi

            # Check expected file exists
            if [ ! -f "$expected" ]; then
                report_skip "$name.ifex → proto" "No expected file: $expected"
                continue
            fi

            # Compare key aspects (not exact match due to comments/whitespace)
            # Test 1: All enum values preserved
            if grep -q "SparseEnum" "$expected" 2>/dev/null; then
                if grep -q "VALUE_ARRAY_START = 20" "$output" 2>/dev/null; then
                    report_pass "$name: enum values preserved"
                else
                    report_fail "$name: enum values" "Expected VALUE_ARRAY_START = 20, values were renumbered"
                fi
            fi

            # Test 2: Type mappings correct
            if grep -q "int8" "$f" 2>/dev/null; then
                if grep -q "sint32.*int8\|int8.*sint32" "$output" 2>/dev/null; then
                    report_pass "$name: int8 → sint32 mapping"
                elif grep -q "int8" "$output" 2>/dev/null; then
                    report_fail "$name: int8 mapping" "int8 not mapped to sint32 (invalid protobuf)"
                fi
            fi

            # Test 3: Struct generation
            if grep -q "message " "$output" 2>/dev/null; then
                report_pass "$name: message generation"
            else
                report_fail "$name: message generation" "No messages found in output"
            fi
        done

        echo ""
        echo "--- Generated test files in $TEST_OUTPUT_DIR/proto/ ---"
        ls -la "$TEST_OUTPUT_DIR/proto/"
        ;;

    idl)
        echo "=== Testing DDS IDL generation ==="
        echo ""

        # Create output directory for test artifacts
        mkdir -p "$TEST_OUTPUT_DIR/idl"

        # Check if custom template exists
        TEMPLATE_DIR=""
        if [ -d "templates/dds-idl" ]; then
            TEMPLATE_DIR="/workspace/templates/dds-idl"
            echo "Using custom template: templates/dds-idl"
        else
            # Check IFEX for IDL template (unlikely to exist)
            TEMPLATE_DIR=$(run_in_container "find /opt/ifex -type d \\( -name 'idl' -o -name 'dds' -o -name 'omg-idl' \\) 2>/dev/null | head -1")
            if [ -n "$TEMPLATE_DIR" ]; then
                echo "Found IFEX IDL template: $TEMPLATE_DIR"
            fi
        fi

        if [ -z "$TEMPLATE_DIR" ]; then
            echo -e "${YELLOW}DDS IDL template not found${NC}"
            echo ""
            echo "To implement DDS IDL generation:"
            echo "  1. Create templates/dds-idl/AST_dds-idl.tpl"
            echo "  2. Run tests again to verify output"
            echo ""
            echo "Available IFEX templates:"
            run_in_container "find /opt/ifex -type d -path '*templates*' -mindepth 1 -maxdepth 1 2>/dev/null"
            report_skip "DDS IDL generation" "Template not implemented yet"
            exit 0
        fi

        echo ""
        echo "--- Running DDS IDL generation tests ---"
        echo ""

        for f in tests/ifex/*.ifex; do
            name=$(basename "$f" .ifex)
            expected="tests/expected/idl/${name}.idl"
            output="$TEST_OUTPUT_DIR/idl/${name}.idl"

            # Generate
            if ! run_in_container "ifexgen -d '$TEMPLATE_DIR' '/workspace/$f'" > "$output" 2>&1; then
                report_fail "$name.ifex → IDL" "Generation failed"
                continue
            fi

            # Test 9: @dds_key annotation generates #pragma keylist
            # Run this before the expected file check since it has inline assertions
            if grep -q "test_dds_key" <<< "$name" 2>/dev/null; then
                # Single key field
                if grep -q '#pragma keylist KeyedMessage id' "$output" 2>/dev/null; then
                    report_pass "$name: single @dds_key generates keylist"
                else
                    report_fail "$name: single @dds_key" "Missing #pragma keylist for KeyedMessage"
                fi
                # Multiple key fields
                if grep -q '#pragma keylist MultiKeyMessage region sensor_id' "$output" 2>/dev/null; then
                    report_pass "$name: multiple @dds_key generates keylist"
                else
                    report_fail "$name: multiple @dds_key" "Missing #pragma keylist for MultiKeyMessage"
                fi
                # No key should have no pragma
                if grep -q '#pragma keylist NoKeyMessage' "$output" 2>/dev/null; then
                    report_fail "$name: no @dds_key" "NoKeyMessage should not have keylist pragma"
                else
                    report_pass "$name: no @dds_key means no keylist"
                fi
                continue  # Done with this test file
            fi

            # Check expected file exists
            if [ ! -f "$expected" ]; then
                report_skip "$name.ifex → IDL" "No expected file: $expected"
                continue
            fi

            # Test 1: Module generation
            if grep -q "module " "$output" 2>/dev/null; then
                report_pass "$name: module generation"
            else
                report_fail "$name: module generation" "No module found in output"
            fi

            # Test 2: Struct generation
            if grep -q "struct " "$output" 2>/dev/null; then
                report_pass "$name: struct generation"
            else
                report_fail "$name: struct generation" "No struct found in output"
            fi

            # Test 3: Type mappings (int32 → long, etc.)
            if grep -q "int32" "$f" 2>/dev/null; then
                if grep -q "long " "$output" 2>/dev/null; then
                    report_pass "$name: int32 → long mapping"
                else
                    report_fail "$name: int32 → long mapping" "int32 not mapped to 'long'"
                fi
            fi

            # Test 4: Array → sequence mapping
            if grep -q "\[\]" "$f" 2>/dev/null; then
                if grep -q "sequence<" "$output" 2>/dev/null; then
                    report_pass "$name: array → sequence mapping"
                else
                    report_fail "$name: array → sequence mapping" "Arrays not mapped to sequence<>"
                fi
            fi

            # Test 5: Enum with @value annotations for sparse enums
            if grep -q "SparseEnum" "$f" 2>/dev/null; then
                if grep -q "@value" "$output" 2>/dev/null; then
                    report_pass "$name: sparse enum @value annotations"
                else
                    report_fail "$name: sparse enum handling" "Missing @value annotations for sparse enums"
                fi
            fi

            # Test 6: Recursive struct flattening
            # DDS IDL cannot handle true recursive types - must flatten by removing
            # the recursive member (container field in FieldValue)
            if grep -q "test_recursive" <<< "$name" 2>/dev/null; then
                # FieldValue should NOT have a "Container container" member (recursion broken)
                # Extract just the FieldValue struct body (between { and };)
                if sed -n '/struct FieldValue/,/};/p' "$output" 2>/dev/null | grep -q "Container container"; then
                    report_fail "$name: recursive struct flattening" "FieldValue still contains Container reference (recursion not broken)"
                else
                    # Container should still reference FieldValue (one direction is OK)
                    if sed -n '/struct Container/,/};/p' "$output" 2>/dev/null | grep -q "sequence<FieldValue>"; then
                        report_pass "$name: recursive struct flattened correctly"
                    else
                        report_fail "$name: recursive struct flattening" "Container should still reference FieldValue"
                    fi
                fi
            fi

            # Test 7: Multi-line descriptions properly commented
            # Each line of a multi-line description should be a separate // comment
            if grep -q "test_multiline" <<< "$name" 2>/dev/null; then
                # Check that multi-line descriptions don't have bare text (syntax error)
                # A bare word like "timestamps" on its own line indicates broken comment
                if grep -E "^[[:space:]]+[a-z]+[,.]?$" "$output" 2>/dev/null | grep -v "^[[:space:]]*//" >/dev/null 2>&1; then
                    report_fail "$name: multi-line comments" "Found uncommented text (broken multi-line description)"
                else
                    # Check that we have multiple consecutive comment lines
                    if grep -A1 "^[[:space:]]*// " "$output" 2>/dev/null | grep -q "^[[:space:]]*// "; then
                        report_pass "$name: multi-line comments handled"
                    else
                        report_fail "$name: multi-line comments" "Multi-line descriptions not converted to multiple comment lines"
                    fi
                fi
            fi

            # Test 8: IFEX includes → IDL #include directives
            if grep -q "test_includes" <<< "$name" 2>/dev/null; then
                if grep -q '#include "test_primitives.idl"' "$output" 2>/dev/null; then
                    report_pass "$name: #include directive generated"
                else
                    report_fail "$name: #include directive" "Missing #include for dependency"
                fi
            fi

        done

        echo ""
        echo "--- Generated test files in $TEST_OUTPUT_DIR/idl/ ---"
        ls -la "$TEST_OUTPUT_DIR/idl/" 2>/dev/null || echo "(no files generated)"
        ;;

    all)
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║            VEP-SCHEMA GENERATOR TEST SUITE                   ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""

        # Export results file so subcommands can use it
        export RESULTS_FILE

        "$0" validate
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        "$0" proto
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        "$0" idl
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo ""

        get_results
        echo "TEST SUMMARY"
        echo "  Passed:  $TESTS_PASSED"
        echo "  Failed:  $TESTS_FAILED"
        echo "  Skipped: $TESTS_SKIPPED"
        echo ""

        if [ $TESTS_FAILED -gt 0 ]; then
            echo -e "${RED}Some tests failed!${NC}"
            exit 1
        else
            echo -e "${GREEN}All tests passed!${NC}"
        fi
        ;;

    *)
        echo "VEP-Schema Generator Test Suite"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  all       Run all tests (default)"
        echo "  validate  Validate IFEX file syntax"
        echo "  proto     Test protobuf generation"
        echo "  idl       Test DDS IDL generation"
        echo "  explore   Explore IFEX tooling structure"
        echo ""
        echo "Test structure:"
        echo "  tests/ifex/           - Test input IFEX files"
        echo "  tests/expected/proto/ - Expected protobuf output"
        echo "  tests/expected/idl/   - Expected DDS IDL output"
        echo "  tests/generated/      - Actual test output (not checked in)"
        exit 1
        ;;
esac
