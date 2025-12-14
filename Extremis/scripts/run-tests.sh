#!/bin/bash
# Run ClipboardCapture unit tests
# This script compiles and runs the standalone test file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_FILE="$PROJECT_DIR/Tests/Utilities/ClipboardCaptureTests.swift"
OUTPUT_DIR="$PROJECT_DIR/.build/tests"

echo "🧪 Running ClipboardCapture Tests..."
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Compile the test file as a standalone executable
swiftc -o "$OUTPUT_DIR/ClipboardCaptureTests" \
    -framework AppKit \
    -framework Foundation \
    "$TEST_FILE" \
    -parse-as-library \
    -emit-executable \
    -Onone \
    2>&1

# Check if compilation succeeded
if [ $? -eq 0 ]; then
    echo "✅ Compilation successful"
    echo ""
    
    # Run the tests
    "$OUTPUT_DIR/ClipboardCaptureTests"
    
    # Capture exit code
    EXIT_CODE=$?
    
    # Clean up
    rm -f "$OUTPUT_DIR/ClipboardCaptureTests"
    
    exit $EXIT_CODE
else
    echo "❌ Compilation failed"
    exit 1
fi

