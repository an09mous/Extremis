#!/bin/bash
# Run all Extremis unit tests
# This script compiles and runs all standalone test files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/.build/tests"

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🧪 Extremis Test Suite"
echo "=================================================="
echo ""

# ------------------------------------------------------------------------------
# Function to run a test suite
# Usage: run_test_suite "Name" "test_file.swift" "framework1" "framework2" ...
# ------------------------------------------------------------------------------
run_test_suite() {
    local name="$1"
    local test_file="$2"
    shift 2
    local frameworks=("$@")

    echo "📦 $name"
    echo "--------------------------------------------------"

    # Build framework flags
    local framework_flags=""
    for fw in "${frameworks[@]}"; do
        framework_flags="$framework_flags -framework $fw"
    done

    local output_name=$(basename "$test_file" .swift)

    # Compile
    if swiftc -o "$OUTPUT_DIR/$output_name" \
        $framework_flags \
        "$test_file" \
        -parse-as-library \
        -emit-executable \
        -Onone \
        2>&1; then

        echo "✅ Compiled $name"
        echo ""

        # Run and capture output
        if "$OUTPUT_DIR/$output_name"; then
            echo ""
        else
            FAILED_SUITES+=("$name")
        fi

        # Clean up
        rm -f "$OUTPUT_DIR/$output_name"
    else
        echo "❌ Compilation failed for $name"
        FAILED_SUITES+=("$name (compilation failed)")
    fi

    echo ""
}

# ------------------------------------------------------------------------------
# Run all test suites
# ------------------------------------------------------------------------------

# 1. LLM Provider Tests (SSE/NDJSON parsing)
run_test_suite "LLM Provider Tests" \
    "$PROJECT_DIR/Tests/LLMProviders/LLMProviderTests.swift" \
    "Foundation"

# 2. ClipboardCapture Tests (marker-based text capture)
run_test_suite "ClipboardCapture Tests" \
    "$PROJECT_DIR/Tests/Utilities/ClipboardCaptureTests.swift" \
    "AppKit" "Foundation"

# 3. ModelConfigLoader Tests (JSON model configuration)
# Note: This test needs to run from the Extremis directory to find Resources/models.json
pushd "$PROJECT_DIR" > /dev/null
run_test_suite "ModelConfigLoader Tests" \
    "$PROJECT_DIR/Tests/LLMProviders/ModelConfigLoaderTests.swift" \
    "Foundation"
popd > /dev/null

# 4. KeychainHelper Tests (secure storage)
run_test_suite "KeychainHelper Tests" \
    "$PROJECT_DIR/Tests/Utilities/KeychainHelperTests.swift" \
    "Foundation" "Security"

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo "=================================================="
echo "OVERALL TEST RESULTS"
echo "=================================================="

if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
    echo "✅ All test suites passed!"
    exit 0
else
    echo "❌ Failed test suites:"
    for suite in "${FAILED_SUITES[@]}"; do
        echo "   • $suite"
    done
    exit 1
fi

