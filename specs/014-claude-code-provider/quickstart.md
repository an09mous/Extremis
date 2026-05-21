# Quickstart: Claude Code CLI Provider

**Feature**: 014-claude-code-provider
**Date**: 2026-05-21

## Prerequisites

1. Claude Code CLI installed: `npm install -g @anthropic-ai/claude-code` or via Homebrew
2. CLI authenticated: Run `claude` interactively and complete login
3. Extremis built and running

## Verify CLI Setup

```bash
# Check CLI is installed
which claude

# Check version
claude --version

# Test non-interactive mode (should return a response)
claude -p "Say hello" --output-format json --model haiku
```

## New Files to Create

| File | Purpose |
|------|---------|
| `Extremis/LLMProviders/ClaudeCodeProvider.swift` | Main provider implementation |
| `Extremis/LLMProviders/ClaudeCodeProcessManager.swift` | Persistent process lifecycle manager |
| `Extremis/LLMProviders/CLIStreamParser.swift` | JSONL stream event parser |
| `Extremis/Tests/LLMProviders/ClaudeCodeProviderTests.swift` | Unit tests |
| `Extremis/Tests/LLMProviders/CLIStreamParserTests.swift` | Stream parsing tests |

## Files to Modify

| File | Change |
|------|--------|
| `Extremis/Core/Models/Generation.swift` | Add `.claudeCode` case to `LLMProviderType` |
| `Extremis/Resources/models.json` | Add `"claudecode"` provider entry |
| `Extremis/LLMProviders/LLMProviderRegistry.swift` | Register `ClaudeCodeProvider` |
| `Extremis/UI/Preferences/ProvidersTab.swift` | Add Claude Code provider row with limitation notice |
| `Extremis/scripts/run-tests.sh` | Add new test files |

## Build & Test

```bash
# Build
cd Extremis && swift build

# Run all tests
./scripts/run-tests.sh

# Run only new tests
swiftc -parse-as-library Tests/LLMProviders/CLIStreamParserTests.swift -o /tmp/test && /tmp/test
swiftc -parse-as-library Tests/LLMProviders/ClaudeCodeProviderTests.swift -o /tmp/test && /tmp/test
```

## Manual Verification

1. Open Extremis → Preferences → Providers
2. Select "Claude Code (CLI)" — process should start warming up (~5s)
3. If CLI not installed, should show clear guidance message
4. Select model (Sonnet recommended)
5. Close Preferences, trigger Option+Space
6. Type a prompt → response should stream in ~2-3s (process already warm)
7. Test multi-turn: send follow-up message → should respond in ~2-3s with conversation context
8. Test cancellation: start generation, press Escape → should stop immediately
9. Switch to another provider → verify Claude Code process is terminated
10. Switch back to Claude Code → verify process restarts
