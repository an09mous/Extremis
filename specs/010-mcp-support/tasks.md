# Tasks: Connectors (MCP Support) - Phase 1

**Input**: Design documents from `/specs/010-mcp-support/`
**Prerequisites**: plan.md (required), spec.md (required), data-model.md (required)

**Scope**: Phase 1 - Custom MCP Servers only (User Stories 2-6)
**Phase 2**: Built-in Connectors (User Story 1) - requires separate approval after Phase 1

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Source**: `Extremis/` at repository root
- **Config**: `~/Library/Application Support/Extremis/`
- **Tests**: `Extremis/Tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, directory structure, and base protocols

- [x] T001 Create `Extremis/Connectors/` directory structure with Models/, Services/, Transport/, Conversion/ subdirectories
- [x] T002 [P] Implement MCP protocol types directly in `Extremis/Connectors/Models/MCPTypes.swift` (MCP Swift SDK requires Swift 6.0+, project uses Swift 5.9)
- [x] T003 [P] Create `Extremis/Core/Protocols/Connector.swift` with Connector protocol, ConnectorState enum

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

### Configuration Models

- [x] T004 [P] Create `Extremis/Connectors/Models/MCPTransportConfig.swift` with MCPTransportType, MCPTransportConfig enum, StdioConfig, HTTPConfig structs
- [x] T005 [P] Create `Extremis/Connectors/Models/CustomMCPServerConfig.swift` with CustomMCPServerConfig struct (id, name, type, enabled, transport)
- [x] T006 [P] Create `Extremis/Connectors/Models/ConnectorConfigFile.swift` with ConnectorConfigFile root struct (version, builtIn dict placeholder, custom array)

### Secrets Management

- [x] T007 Create `Extremis/Connectors/Models/ConnectorSecrets.swift` with ConnectorSecrets struct, ConnectorKeychainKey enum
- [x] T008 Create `Extremis/Connectors/Services/ConnectorSecretsStorage.swift` using existing KeychainHelper for save/load/delete secrets

### Tool Models

- [x] T009 [P] Create `Extremis/Connectors/Models/JSONSchema.swift` with JSONSchema, JSONSchemaProperty structs
- [x] T010 [P] Create `Extremis/Connectors/Models/ConnectorTool.swift` with ConnectorTool struct (originalName, description, inputSchema, connectorID, connectorName, disambiguated name property)
- [x] T011 [P] Create `Extremis/Connectors/Models/ToolCall.swift` with ToolCall struct (id, toolName, connectorID, arguments, requestedAt)
- [x] T012 [P] Create `Extremis/Connectors/Models/ToolResult.swift` with ToolResult struct, ToolOutcome enum, ToolContent struct, ToolError struct

### Transport Layer

- [x] T013 Create `Extremis/Connectors/Transport/MCPTransport.swift` with MCPTransport protocol (connect, disconnect, sendRequest, tools property)
- [x] T014 Create `Extremis/Connectors/Transport/StdioTransport.swift` implementing MCPTransport using Foundation.Process for local MCP servers
- [x] T015 Create `Extremis/Connectors/Transport/HTTPTransport.swift` implementing MCPTransport for remote HTTP/SSE servers

### Config Persistence

- [x] T016 Create `Extremis/Connectors/Services/ConnectorConfigStorage.swift` for JSON file read/write at `~/Library/Application Support/Extremis/connectors.json`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 2 - Add Custom MCP Server (Priority: P0)

**Goal**: Users can add, edit, and delete custom MCP server configurations via Preferences UI

**Independent Test**: Open Preferences > Connectors tab > Add custom MCP server with name/command > Save > Close and reopen Preferences > Verify server appears

### Implementation for User Story 2

- [ ] T017 [US2] Create `Extremis/Connectors/CustomMCPConnector.swift` implementing Connector protocol with config, state, tools properties
- [ ] T018 [US2] Create `Extremis/UI/Preferences/ConnectorsTab.swift` SwiftUI view with "Custom MCP Servers" section and "+ Add New" button
- [ ] T019 [US2] Create `Extremis/UI/Preferences/AddEditMCPServerSheet.swift` SwiftUI sheet for name, type (stdio/http), command/URL, args, env vars, API keys sections
- [ ] T020 [US2] Implement add server flow in ConnectorsTab: show sheet > save to ConnectorConfigStorage > save secrets to Keychain via ConnectorSecretsStorage
- [ ] T021 [US2] Implement edit server flow in ConnectorsTab: load existing config > show sheet > save changes
- [ ] T022 [US2] Implement delete server flow in ConnectorsTab: confirm dialog > remove from config > delete secrets from Keychain
- [ ] T023 [US2] Add ConnectorsTab to PreferencesView tab list in `Extremis/UI/Preferences/PreferencesView.swift`
- [ ] T024 [US2] Add unit test `Extremis/Tests/Connectors/ConnectorConfigStorageTests.swift` for CRUD operations

**Checkpoint**: User Story 2 complete - users can add/edit/delete custom MCP servers

---

## Phase 4: User Story 3 - Connect to Connector (Priority: P0)

**Goal**: Extremis connects to enabled custom MCP servers and discovers their tools

**Independent Test**: Add and enable a custom MCP server > Restart app (or trigger connect) > Verify status shows "Connected" > Verify discovered tools are listed

### Implementation for User Story 3

- [ ] T025 [US3] Create `Extremis/Connectors/Services/ConnectorRegistry.swift` singleton managing CustomMCPConnector instances (like LLMProviderRegistry)
- [ ] T026 [US3] Implement CustomMCPConnector.connect() using StdioTransport or HTTPTransport based on config type
- [ ] T027 [US3] Implement tool discovery in CustomMCPConnector: after MCP initialize handshake, call tools/list and populate tools array
- [ ] T028 [US3] Add auto-connect on app startup: in AppDelegate.swift applicationDidFinishLaunching, call ConnectorRegistry.shared.connectAllEnabled()
- [ ] T029 [US3] Implement auto-reconnect with retry logic in ConnectorRegistry: max 3 retries with exponential backoff (1s, 2s, 4s)
- [ ] T030 [US3] Add connection status indicators to ConnectorsTab: 🟢 Connected, 🟡 Connecting, ⚪ Disconnected, 🔴 Error
- [ ] T031 [US3] Display discovered tools list for each connected server in ConnectorsTab (collapsible section)
- [ ] T032 [US3] Handle connection errors: show error message in UI, log details, allow manual retry via "Reconnect" button

**Checkpoint**: User Story 3 complete - connectors establish connections and discover tools

---

## Phase 5: User Story 4 - Use Connector Tools in Chat (Priority: P0)

**Goal**: LLM can use tools from connected connectors during chat conversations

**Independent Test**: Connect an MCP server with tools > Ask a question in chat that requires a tool > Verify LLM uses the tool > Verify tool result appears in response

### Schema Conversion

- [ ] T033 [P] [US4] Create `Extremis/Connectors/Conversion/ToolSchemaConverter.swift` with methods to convert ConnectorTool to OpenAI function format and Anthropic tool format
- [ ] T034 [P] [US4] Add unit test `Extremis/Tests/Connectors/ToolSchemaConverterTests.swift` for OpenAI and Anthropic format conversion

### Tool Execution

- [ ] T035 [US4] Create `Extremis/Connectors/Services/ToolExecutor.swift` with execute(toolCalls:) method supporting parallel execution via TaskGroup
- [ ] T036 [US4] Implement tool routing in ToolExecutor: map tool name to connector, call connector.executeTool()
- [ ] T037 [US4] Implement 30-second timeout for tool execution with proper cancellation
- [ ] T038 [US4] Add unit test `Extremis/Tests/Connectors/ToolExecutorTests.swift` for parallel execution and timeout handling

### LLM Provider Integration

- [ ] T039 [US4] Extend `Extremis/Core/Protocols/LLMProvider.swift` with generateChatWithTools(messages:tools:) method
- [ ] T040 [US4] Create `Extremis/Connectors/Models/GenerationWithToolCalls.swift` with content, toolCalls array, isComplete flag, stopReason
- [ ] T041 [US4] Update `Extremis/LLMProviders/OpenAIProvider.swift` to implement generateChatWithTools with function calling
- [ ] T042 [US4] Update `Extremis/LLMProviders/AnthropicProvider.swift` to implement generateChatWithTools with tool use
- [ ] T043 [US4] Update `Extremis/LLMProviders/PromptBuilder.swift` to include tool definitions when tools are available

### Chat Integration

- [ ] T044 [US4] Create `Extremis/Connectors/Models/ChatToolCall.swift` with ChatToolCall struct, ChatToolCallState enum
- [ ] T045 [US4] Create `Extremis/Connectors/Models/ChatToolResult.swift` with ChatToolResult struct
- [ ] T046 [US4] Extend ChatMessage in `Extremis/Core/Models/ChatMessage.swift` with optional toolCalls and toolResult properties
- [ ] T047 [US4] Create `Extremis/UI/PromptWindow/ToolIndicatorView.swift` SwiftUI view showing "Using tool: [connector]: [name]..." during execution
- [ ] T048 [US4] Update `Extremis/UI/PromptWindow/ChatMessageView.swift` to display ToolIndicatorView for messages with tool calls
- [ ] T049 [US4] Implement tool execution loop in chat: detect tool calls from LLM > execute tools > inject results > continue generation

**Checkpoint**: User Story 4 complete - LLM can use connector tools in conversations

---

## Phase 6: User Story 5 - Manage Multiple Connectors (Priority: P1)

**Goal**: Users can use multiple connectors simultaneously with disambiguated tool names

**Independent Test**: Enable 2+ custom MCP servers > Verify all show in Connectors tab with individual status > Verify tools from all servers are available in chat

### Implementation for User Story 5

- [ ] T050 [US5] Update ConnectorRegistry to manage multiple CustomMCPConnector instances concurrently
- [ ] T051 [US5] Implement tool name disambiguation in ConnectorTool.name property using underscore prefix format (e.g., `myserver_read_file`)
- [ ] T052 [US5] Update ToolExecutor to aggregate tools from all connected connectors for LLM tool definitions
- [ ] T053 [US5] Update ConnectorsTab to list all custom servers with individual enable/disable toggles and status indicators
- [ ] T054 [US5] Handle connector failures independently: one connector error doesn't affect others

**Checkpoint**: User Story 5 complete - multiple connectors work simultaneously

---

## Phase 7: User Story 6 - Enable/Disable Connectors (Priority: P1)

**Goal**: Users can enable/disable individual connectors without removing their configurations

**Independent Test**: Disable a connected connector > Verify status changes to Disconnected > Verify tools no longer available > Re-enable > Verify reconnects

### Implementation for User Story 6

- [ ] T055 [US6] Add enabled toggle to each connector row in ConnectorsTab
- [ ] T056 [US6] Implement enable flow: update config > call ConnectorRegistry.connect(connectorID:)
- [ ] T057 [US6] Implement disable flow: update config > call ConnectorRegistry.disconnect(connectorID:)
- [ ] T058 [US6] Preserve config when disabled: server still appears in list with preserved settings
- [ ] T059 [US6] Update ToolExecutor to only provide tools from enabled AND connected connectors

**Checkpoint**: User Story 6 complete - connectors can be enabled/disabled independently

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Quality improvements, documentation, and integration testing

- [ ] T060 [P] Add error logging throughout Connectors module using existing logging patterns
- [ ] T061 [P] Update `Extremis/CLAUDE.md` with Connectors module documentation (patterns, key files)
- [ ] T062 [P] Update `Extremis/README.md` with Connectors feature description and configuration instructions
- [ ] T063 Create `Extremis/Resources/PromptTemplates/tool_context.hbs` for tool-aware system prompt additions (if needed)
- [ ] T064 Manual QA: Test all connector flows per quickstart.md scenarios
- [ ] T065 Run full test suite via `./scripts/run-tests.sh` and verify all pass
- [ ] T066 Build release and verify no warnings: `swift build -c release`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US2 (Add Server) can start immediately after Foundational
  - US3 (Connect) depends on US2 for server configuration
  - US4 (Use Tools) depends on US3 for connection capability
  - US5 (Multiple) depends on US3, can parallel with US4
  - US6 (Enable/Disable) depends on US3, can parallel with US4/US5
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

```
Foundational (Phase 2)
        │
        ▼
    US2: Add Server (P0)
        │
        ▼
    US3: Connect (P0)
        │
        ├──────────────────────┐
        ▼                      ▼
    US4: Use Tools (P0)    US5: Multiple (P1)
        │                      │
        └──────────────────────┤
                               ▼
                           US6: Enable/Disable (P1)
```

### Within Each User Story

- Models before services
- Services before UI
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Foundational model tasks (T004-T012) can run in parallel
- T033-T034 (Schema Conversion) can run in parallel with T035-T038 (Tool Execution)
- US5 and US6 can be developed in parallel after US3 is complete
- All Polish tasks marked [P] can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# Launch all model files together (no dependencies between them):
T004: Create MCPTransportConfig.swift
T005: Create CustomMCPServerConfig.swift
T006: Create ConnectorConfigFile.swift
T009: Create JSONSchema.swift
T010: Create ConnectorTool.swift
T011: Create ToolCall.swift
T012: Create ToolResult.swift

# Then secrets (depends on models):
T007: Create ConnectorSecrets.swift
T008: Create ConnectorSecretsStorage.swift

# Then transport (depends on models):
T013: Create MCPTransport.swift
T014: Create StdioTransport.swift (depends on T013)
T015: Create HTTPTransport.swift (depends on T013)
```

---

## Implementation Strategy

### MVP First (User Stories 2-4 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 2 - Add Custom MCP Server
4. Complete Phase 4: User Story 3 - Connect to Connector
5. Complete Phase 5: User Story 4 - Use Tools in Chat
6. **STOP and VALIDATE**: Test end-to-end with a real MCP server
7. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add US2 (Add Server) → Test independently → Config works
3. Add US3 (Connect) → Test independently → Connections work
4. Add US4 (Use Tools) → Test independently → Deploy/Demo (MVP!)
5. Add US5 (Multiple) → Test independently → Power user feature
6. Add US6 (Enable/Disable) → Test independently → Full feature set

### Single Developer Strategy (Recommended)

Execute in strict order: Phase 1 → Phase 2 → US2 → US3 → US4 → US5 → US6 → Polish

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| Setup | T001-T003 | Directory structure, dependencies, base protocol |
| Foundational | T004-T016 | Models, secrets, transport, config persistence |
| US2: Add Server | T017-T024 | Add/edit/delete custom MCP servers |
| US3: Connect | T025-T032 | Connection lifecycle, tool discovery |
| US4: Use Tools | T033-T049 | Schema conversion, execution, LLM integration |
| US5: Multiple | T050-T054 | Multiple concurrent connectors |
| US6: Enable/Disable | T055-T059 | Toggle connectors without deletion |
| Polish | T060-T066 | Documentation, QA, testing |

**Total**: 66 tasks
- Setup: 3 tasks
- Foundational: 13 tasks
- US2: 8 tasks
- US3: 8 tasks
- US4: 17 tasks
- US5: 5 tasks
- US6: 5 tasks
- Polish: 7 tasks

**Parallel Opportunities**: ~30% of tasks can run in parallel within their phases.

---

## Notes

- [P] tasks = different files, no dependencies
- [USx] label maps task to specific user story for traceability
- Each user story is independently testable after completion
- Verify tests pass before marking story complete
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Phase 2 (Built-in Connectors) will be planned separately after Phase 1 approval
