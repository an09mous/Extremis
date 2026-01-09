#!/bin/bash
# Run all Extremis unit tests
# This script compiles and runs all standalone test files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/.build/tests"

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SUITES=0
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

    ((TOTAL_SUITES++))

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

        # Run and capture output, extract pass/fail counts
        local output
        output=$("$OUTPUT_DIR/$output_name" 2>&1)
        local exit_code=$?
        echo "$output"

        # Extract passed/failed counts from output (handles both formats)
        # Format 1: "Passed: N" / "Failed: N"
        # Format 2: "N passed, N failed"
        local passed=0
        local failed=0

        if echo "$output" | grep -q "Passed:"; then
            passed=$(echo "$output" | grep "^Passed:" | tail -1 | awk '{print $2}')
            failed=$(echo "$output" | grep "^Failed:" | tail -1 | awk '{print $2}')
        elif echo "$output" | grep -q "passed,"; then
            passed=$(echo "$output" | grep -o "[0-9]* passed" | tail -1 | awk '{print $1}')
            failed=$(echo "$output" | grep -o "[0-9]* failed" | tail -1 | awk '{print $1}')
        fi

        # Add to totals
        TOTAL_PASSED=$((TOTAL_PASSED + ${passed:-0}))
        TOTAL_FAILED=$((TOTAL_FAILED + ${failed:-0}))

        if [ $exit_code -ne 0 ]; then
            FAILED_SUITES+=("$name")
        fi

        echo ""

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

# 2. PromptBuilder Truncation Tests (context truncation logic)
run_test_suite "PromptBuilder Truncation Tests" \
    "$PROJECT_DIR/Tests/LLMProviders/PromptBuilderTruncationTests.swift" \
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

# 5. ChatConversation Tests (retry functionality and conversation management)
run_test_suite "ChatConversation Tests" \
    "$PROJECT_DIR/Tests/Core/ChatConversationTests.swift" \
    "Foundation"

# 6. SessionManager Tests (generation state tracking and session switching)
run_test_suite "SessionManager Tests" \
    "$PROJECT_DIR/Tests/Core/SessionManagerTests.swift" \
    "Foundation"

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo "=================================================="
echo "COMBINED TEST RESULTS"
echo "=================================================="
echo ""
echo "Test Suites: $TOTAL_SUITES"
echo "Total Tests: $((TOTAL_PASSED + TOTAL_FAILED))"
echo ""
echo "  ✓ Passed: $TOTAL_PASSED"
echo "  ✗ Failed: $TOTAL_FAILED"
echo ""
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

