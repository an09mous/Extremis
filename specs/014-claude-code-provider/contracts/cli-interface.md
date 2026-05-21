# CLI Interface Contract: Claude Code

**Feature**: 014-claude-code-provider
**Date**: 2026-05-21

## Invocation Contract

### Persistent Process Launch

```bash
claude -p \
  --input-format stream-json \
  --output-format stream-json \
  --model <model_alias> \
  --allowedTools "Tool1,Tool2,Tool3" \
  --append-system-prompt "<extremis_system_prompt>" \
  --verbose \
  --include-partial-messages
```

The process stays alive, reading JSONL from stdin and writing JSONL to stdout.

### Sending a Message (stdin → process)

```json
{"type":"user_message","content":"Hello, explain this code"}
```

### Expected Response Events (process → stdout)

The process emits JSONL events on stdout in response to each message.

## Stream-JSON Output Contract (JSONL)

Each line of stdout is a valid JSON object. Key event types:

### Init Event (once at startup)
```json
{"type":"system","subtype":"init","session_id":"abc123","tools":["Bash","Read","Edit"]}
```

### Status Event
```json
{"type":"system","subtype":"status","status":"requesting","session_id":"abc123"}
```

### Message Start
```json
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","role":"assistant"}}}
```

### Text Delta
```json
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello "}}}
```

### Thinking Delta
```json
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The user is asking..."}}}
```

### Tool Use Start
```json
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_123","name":"Bash","input":{}}}}
```

### Tool Use Input Delta
```json
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"command\":\"ls"}}}
```

### Assistant Message (full, with --include-partial-messages)
```json
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","role":"assistant","content":[{"type":"text","text":"Hello!"}]}}
```

### Message Stop
```json
{"type":"stream_event","event":{"type":"message_stop"}}
```

### Result (end of turn)
```json
{"type":"result","subtype":"success","session_id":"abc123","total_cost_usd":0.001,"duration_ms":2500,"duration_api_ms":1870,"ttft_ms":1746,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":50}}
```

### Error Result
```json
{"type":"result","subtype":"error","error":"Not logged in"}
```

### Rate Limit Event
```json
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1779373200,"rateLimitType":"five_hour"}}
```

## Error Contract

### Process Exit
- Exit code `0`: Normal termination (process was asked to stop)
- Exit code non-zero: Unexpected crash — trigger auto-restart

### Stderr Patterns
| Pattern | Meaning |
|---------|---------|
| `Not logged in` | CLI not authenticated |
| `Invalid API key` | Bad API key in env |
| `429` / `rate limit` | Rate limited |
| `API Error: 500` | Server error |

## Model Aliases

| Alias | Maps To | Notes |
|-------|---------|-------|
| `sonnet` | Latest Sonnet (4.6) | Default, recommended |
| `opus` | Latest Opus (4.7) | Most capable |
| `haiku` | Latest Haiku (4.5) | Fastest, cheapest |
| `default` | Account default | Varies by subscription |

## Authentication Detection

```bash
# Check if CLI exists
which claude  # exit 0 = found, exit 1 = not found

# Auth is verified implicitly when the persistent process starts
# If not authenticated, the init event or first result will contain an error
```
