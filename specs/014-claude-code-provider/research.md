# Research: Claude Code CLI Provider

**Feature**: 014-claude-code-provider
**Date**: 2026-05-21

## R1: Claude Code CLI Programmatic Mode

**Decision**: Use persistent process with bidirectional stream-json I/O (`--input-format stream-json --output-format stream-json`).

**Rationale**: Benchmarking revealed ~5.5s CLI startup overhead per process spawn. A persistent process eliminates this cost for subsequent messages, matching API-provider latency (~2-3s TTFT). This is the same approach used by VS Code's Claude Code extension.

**Alternatives considered**:
- `claude -p` per message: ~8s TTFT per message due to process spawn + CLI init. Rejected — unacceptable for chat UX.
- `--bare` mode: Skips hooks/plugins/MCP/OAuth, requires explicit API key. Rejected because the whole point is to use the CLI's built-in subscription auth.
- Agent SDK (Python/TypeScript): Would require bundling a Python/Node runtime. Rejected per user's constraint.
- Direct OAuth token extraction: Banned by Anthropic ToS. Rejected.

**Key CLI flags (at process launch)**:
| Flag | Purpose |
|------|---------|
| `-p` | Non-interactive print mode |
| `--input-format stream-json` | Accept JSONL messages on stdin |
| `--output-format stream-json` | Emit JSONL events on stdout |
| `--model <alias>` | Model selection (opus, sonnet, haiku, default) |
| `--allowedTools "Tool1,Tool2"` | Control which tools CLI can auto-execute |
| `--append-system-prompt "text"` | Inject Extremis system prompt |
| `--verbose` | Include all event types in stream |
| `--include-partial-messages` | Include partial content blocks |

**Reference**: VS Code extension launches claude with:
```
claude --output-format stream-json --verbose --input-format stream-json
  --model default --permission-mode acceptEdits --include-partial-messages
```

## R2: Stream-JSON Event Format

**Decision**: Parse JSONL output filtering for `stream_event` types to extract text deltas and tool events.

**Rationale**: The stream-json format provides granular events matching the Anthropic API streaming format. Text arrives as `content_block_delta` events with `text_delta` type. Tool use arrives as `content_block_start` (tool_use type) followed by `input_json_delta` events.

**Event taxonomy**:

```
system/init          → Session initialization (session_id, model, tools)
stream_event         → Content streaming events:
  content_block_start  → New content block (text or tool_use)
  content_block_delta  → Incremental content (text_delta or input_json_delta)
  content_block_stop   → Block complete
assistant            → Full assistant message (with --include-partial-messages)
result/success       → Completion (session_id, cost, usage, duration)
result/error         → Error during generation
```

**Text delta extraction**:
```json
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}
```

**Tool use extraction**:
```json
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_123","name":"bash","input":{}}}}
```

## R3: Multi-Turn Conversation Strategy

**Decision**: CLI manages conversation history internally via the persistent process.

**Rationale**: With a persistent bidirectional stream-json process, the CLI maintains full conversation state. Extremis sends individual `user_message` events via stdin. No need to serialize/reconstruct history per turn.

**Alternatives considered**:
- Full prompt reconstruction per turn: Stateless but adds complexity and hits stdin size limits for long conversations. Rejected after latency benchmarking showed per-spawn overhead is the dominant cost.
- `--resume <session_id>`: Per-message process spawn with session resume. Still pays ~5.5s spawn overhead. Rejected.

**Implementation**: Send `{"type":"user_message","content":"<text>"}` JSONL line to stdin. CLI responds with stream events on stdout.

## R4: Model Selection

**Decision**: Expose CLI model aliases (opus, sonnet, haiku) as selectable models in Extremis.

**Rationale**: Claude Code CLI uses simple aliases rather than full model IDs. These map to the latest versions automatically (e.g., "sonnet" → Claude Sonnet 4.6). This means Extremis stays current without updating model configs.

**Model entries for models.json**:
| ID | Name | Description | Tools | Vision |
|----|------|-------------|-------|--------|
| `sonnet` | Sonnet | Recommended daily coding model | Yes | Yes |
| `opus` | Opus | Maximum capability, complex reasoning | Yes | Yes |
| `haiku` | Haiku | Fast, lightweight (3x cost savings) | Yes | Yes |

**Default**: `sonnet` (best balance of speed and capability)

## R5: Authentication Detection

**Decision**: Check CLI availability via `which claude` and auth status by running a minimal test command.

**Rationale**: The CLI manages its own auth (OAuth login, API key, env vars). Extremis only needs to detect if the CLI is installed and authenticated, not manage credentials.

**Detection approach**:
1. `which claude` or check custom path → CLI installed?
2. `claude -p "hi" --output-format json --model haiku --max-turns 0` → authenticated? Parse result for errors.

**Error patterns**:
- Not installed: Process launch fails
- Not authenticated: stderr contains "Not logged in" or "Invalid API key"
- Rate limited: stderr contains "429"

## R6: Tool Approval & Allowed Tools

**Decision**: Query CLI for available tools, present checklist in Preferences, pass selected tools via `--allowedTools`.

**Rationale**: The `--allowedTools` flag controls what the CLI can auto-execute. By querying available tools and letting users configure them, we provide control without reimplementing approval logic.

**Tool query approach**: There is no dedicated `claude tools list` command. Available tools are reported in the `system/init` event of stream-json output. We can capture these from any generation's init event and cache them.

**Alternatives considered**:
- `--permission-mode dontAsk`: Denies anything not in allow rules. More restrictive but less configurable.
- No tools at all: Pass empty `--allowedTools ""` to disable all tool execution.

## R7: Process Lifecycle Management

**Decision**: Use Swift `Process` (Foundation) for a single persistent subprocess with bidirectional pipe-based I/O.

**Rationale**: Matches existing patterns in the codebase (ProcessTransport in MCP connector). Foundation's Process class provides launch/terminate with proper cleanup. The persistent process pattern matches VS Code's approach.

**Key considerations**:
- Single Process instance launched when provider is activated
- stdin Pipe for sending JSONL messages, stdout Pipe for reading JSONL events, stderr Pipe for error capture
- Process stays alive across all chat messages and sessions
- `process.terminationHandler` for crash detection and auto-restart
- Process environment inherits from parent (picks up PATH, auth env vars)
- Terminate on provider switch or app quit

## R9: Latency Benchmarks (Local Machine)

**Measured on**: macOS ARM64, Claude Code CLI v2.1.144

**Per-message spawn approach** (rejected):
| Metric | Haiku | Sonnet |
|--------|-------|--------|
| Process spawn | ~3.3s | ~3.3s |
| CLI initialization | ~2.4s | ~2.4s |
| API TTFT | 1.3-2.6s | 1.8-2.4s |
| **Total wall time** | **~8s** | **~8s** |

**Persistent process approach** (chosen):
| Metric | Expected |
|--------|----------|
| One-time startup | ~5.5s (paid once at provider activation) |
| Per-message TTFT | ~2-3s (API latency only) |
| Streaming throughput | Same as API providers |

**Key finding**: The CLI binary is native ARM64 (not Node.js). The ~5.5s overhead is from auth handshake, tool registry setup, and session management — NOT from project context scanning (same overhead measured from `/tmp` with no CLAUDE.md).

**`--bare` mode**: 50ms startup but requires explicit API key, defeating the subscription auth purpose.

## R8: Existing Provider Integration Pattern

**Decision**: Follow Ollama provider pattern (no API key, dynamic model discovery, connection check).

**Rationale**: OllamaProvider is the closest existing analog — local provider without API key. ClaudeCodeProvider will follow the same patterns for `isConfigured`, `configure()`, and model management.

**Key patterns to follow**:
- `isConfigured` returns CLI availability + auth status (like Ollama's `serverConnected`)
- `configure()` repurposes apiKey parameter for custom binary path
- Model list is static (CLI aliases) but could be extended
- `@Published` state for reactive UI updates
- UserDefaults for persisting model selection and custom binary path
- Register in `LLMProviderRegistry.registerDefaultProviders()`
- Add case to `LLMProviderType` enum

## Sources

- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless)
- [Claude Code Model Configuration](https://code.claude.com/docs/en/model-config)
- [Claude Code Authentication](https://code.claude.com/docs/en/authentication)
- [Stream-JSON Event Cheatsheet](https://takopi.dev/reference/runners/claude/stream-json-cheatsheet/)
- [Claude Code Sessions](https://code.claude.com/docs/en/agent-sdk/sessions)
