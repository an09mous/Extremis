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

# 3. PromptBuilder Intent Tests (intent-based prompt injection framework)
run_test_suite "PromptBuilder Intent Tests" \
    "$PROJECT_DIR/Tests/LLMProviders/PromptBuilderTests.swift" \
    "Foundation"

# 4. ModelConfigLoader Tests (JSON model configuration)
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

# 7. SummarizationManager Tests (session summarization and context preservation)
# Note: This test is fully self-contained with embedded type definitions
run_test_suite "SummarizationManager Tests" \
    "$PROJECT_DIR/Tests/Core/SummarizationManagerTests.swift" \
    "Foundation"

# 8. Tool Models Tests (ToolCall, ToolResult, ToolExecutionRound, etc.)
run_test_suite "Tool Models Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolModelsTests.swift" \
    "Foundation"

# 9. Tool Schema Converter Tests (provider-specific schema conversion)
run_test_suite "Tool Schema Converter Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolSchemaConverterTests.swift" \
    "Foundation"

# 10. Tool Enabled Chat Service Tests (tool execution loop and state management)
run_test_suite "Tool Enabled Chat Service Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolEnabledChatServiceTests.swift" \
    "Foundation"

# 11. Tool Persistence Tests (ToolCallRecord, ToolResultRecord, ToolExecutionRoundRecord)
run_test_suite "Tool Persistence Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolPersistenceTests.swift" \
    "Foundation"

# 12. Process Transport Tests (MCP connector edge cases, JSON detection, tool naming)
run_test_suite "Process Transport Tests" \
    "$PROJECT_DIR/Tests/Connectors/ProcessTransportTests.swift" \
    "Foundation"

# 13. Connector Config Storage Tests (CRUD operations for connector config persistence)
run_test_suite "Connector Config Storage Tests" \
    "$PROJECT_DIR/Tests/Connectors/ConnectorConfigStorageTests.swift" \
    "Foundation"

# 14. Tool Executor Tests (parallel execution, timeout handling)
run_test_suite "Tool Executor Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolExecutorTests.swift" \
    "Foundation"

# 15. Tool Approval Manager Tests (approval flow, rule matching, session memory)
run_test_suite "Tool Approval Manager Tests" \
    "$PROJECT_DIR/Tests/Core/ToolApprovalManagerTests.swift" \
    "Foundation"

# 16. Sudo Mode Tests (sudo mode bypass for tool approval)
run_test_suite "Sudo Mode Tests" \
    "$PROJECT_DIR/Tests/Core/SudoModeTests.swift" \
    "Foundation"

# 18. Model Capability Tests (ModelCapabilities struct, tool support detection)
run_test_suite "Model Capability Tests" \
    "$PROJECT_DIR/Tests/Core/ModelCapabilityTests.swift" \
    "Foundation"

# 19. Command Tests (Command model, CommandConfigFile, storage operations)
run_test_suite "Command Tests" \
    "$PROJECT_DIR/Tests/Commands/CommandTests.swift" \
    "Foundation"

# 20. Command Storage Tests (Persistence CRUD operations)
run_test_suite "Command Storage Tests" \
    "$PROJECT_DIR/Tests/Commands/CommandStorageTests.swift" \
    "Foundation"

# 21. Shell Command Tests (Risk classification, validation, pattern matching)
run_test_suite "Shell Command Tests" \
    "$PROJECT_DIR/Tests/Tools/Shell/ShellCommandTests.swift" \
    "Foundation"

# 22. Shell Approval Security Tests (CRITICAL: Pattern matching security)
run_test_suite "Shell Approval Security Tests" \
    "$PROJECT_DIR/Tests/Tools/Shell/ShellApprovalSecurityTests.swift" \
    "Foundation"

# 23. GitHub Connector Tests (Built-in GitHub connector)
run_test_suite "GitHub Connector Tests" \
    "$PROJECT_DIR/Tests/Connectors/GitHubConnectorTests.swift" \
    "Foundation"

# 24. WebFetch Connector Tests (Built-in Web Fetch connector)
run_test_suite "WebFetch Connector Tests" \
    "$PROJECT_DIR/Tests/Connectors/WebFetchConnectorTests.swift" \
    "Foundation"

# 25. Sound Notification Tests (Background sound notifications)
run_test_suite "Sound Notification Tests" \
    "$PROJECT_DIR/Tests/Core/SoundNotificationTests.swift" \
    "Foundation"

run_test_suite "Stale Batch Cleanup Tests" \
    "$PROJECT_DIR/Tests/Core/StaleBatchCleanupTests.swift" \
    "Foundation"

# 28. Tool Fallback Tests (empty message filter, fallback message construction)
run_test_suite "Tool Fallback Tests" \
    "$PROJECT_DIR/Tests/Connectors/ToolFallbackTests.swift" \
    "Foundation"

# 27. Markdown Rendering Tests (language name mapping, helpers)
run_test_suite "Markdown Rendering Tests" \
    "$PROJECT_DIR/Tests/UI/MarkdownRenderingTests.swift" \
    "Foundation"

# 28. Design System Tests (token ordering and value invariants)
run_test_suite "Design System Tests" \
    "$PROJECT_DIR/Tests/UI/DesignSystemTests.swift" \
    "Foundation"

# 29. Message Attachment Tests (ImageAttachment, MessageAttachment, ChatMessage attachments)
run_test_suite "Message Attachment Tests" \
    "$PROJECT_DIR/Tests/Core/MessageAttachmentTests.swift" \
    "Foundation"

# 30. Image Processor Tests (resize calculations, encoding selection)
run_test_suite "Image Processor Tests" \
    "$PROJECT_DIR/Tests/Utilities/ImageProcessorTests.swift" \
    "Foundation"

# 31. Persisted Message Attachment Tests (PersistedAttachmentRef, backward compat)
run_test_suite "Persisted Message Attachment Tests" \
    "$PROJECT_DIR/Tests/Core/PersistedMessageAttachmentTests.swift" \
    "Foundation"

# 32. Model Capability Image Tests (supportsImages in ModelCapabilities and LLMModel)
run_test_suite "Model Capability Image Tests" \
    "$PROJECT_DIR/Tests/Core/ModelCapabilityImageTests.swift" \
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

