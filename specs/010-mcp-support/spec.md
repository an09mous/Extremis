# Feature Specification: Connectors (MCP Support)

**Feature Branch**: `010-mcp-support`
**Created**: 2026-01-18
**Status**: Draft
**Input**: User description: "Build MCP support in Extremis. Users should be able to configure in their local or remote MCP servers and Extremis will start using that MCP servers in the chat."

## Overview

Connectors enable Extremis to integrate with external tools and services. The system supports two types of connectors:

1. **Built-in Connectors** - Pre-configured integrations (GitHub, Brave Search, Jira, etc.) that users can enable with minimal setup
2. **Custom MCP Servers** - User-configured MCP (Model Context Protocol) servers for advanced use cases

Both types appear in the unified "Connectors" preferences tab, providing a consistent experience.

**Implementation is split into two phases:**
- **Phase 1**: Custom MCP Servers (User Stories 2-6)
- **Phase 2**: Built-in Connectors (User Story 1) - requires separate approval

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Built-in Connector (Priority: P0) *(Phase 2)*

As a user, I want to enable a built-in connector (like GitHub or Brave Search) so that I can use its tools in my chat conversations with minimal configuration.

**Why this priority**: Built-in connectors provide immediate value with minimal friction - this is the primary way most users will interact with the feature.

**Implementation Phase**: Phase 2 (requires separate approval after Phase 1 is complete)

**Independent Test**: Can be fully tested by opening Preferences, navigating to Connectors, clicking "Connect" on a built-in connector (e.g., GitHub), completing authentication, and verifying the connector shows as connected.

**Acceptance Scenarios**:

1. **Given** I am in the Connectors preferences tab, **When** I view the Built-in Connectors section, **Then** I see a list of available connectors (GitHub, Brave Search, Jira, etc.) with their connection status.
2. **Given** I see a built-in connector that is not connected, **When** I click "Connect", **Then** I am guided through the authentication/setup process for that connector.
3. **Given** I have connected a built-in connector, **When** I close and reopen Extremis, **Then** my connector remains connected and its tools are available.
4. **Given** I have a connected built-in connector, **When** I click "Disconnect", **Then** the connector is disabled and its tools are no longer available.
5. **Given** npx is not installed on my system, **When** I view a built-in connector, **Then** it shows as "Unavailable" with a message explaining I need to install Node.js.

---

### User Story 2 - Add Custom MCP Server (Priority: P0) *(Phase 1)*

As a power user, I want to add a custom MCP server configuration so that I can connect to tools and resources not available as built-in connectors.

**Why this priority**: Custom MCP servers are the foundation of the Connectors feature and must work before built-in connectors can be added.

**Implementation Phase**: Phase 1 (current focus)

**Independent Test**: Can be fully tested by opening Preferences, navigating to Connectors, adding a custom MCP server (name, command/URL), and verifying the configuration is saved and persisted.

**Acceptance Scenarios**:

1. **Given** I am in the Connectors preferences tab, **When** I click "Add Custom MCP Server" in the Custom section, **Then** I can configure a new server with name, command/URL, environment variables, and API keys.
2. **Given** I am adding a custom MCP server, **When** I enter API keys in the dedicated "API Keys" section, **Then** they are stored securely in Keychain (not in the config file).
3. **Given** I have added a custom MCP server, **When** I close and reopen Extremis, **Then** my server configuration is preserved and visible.
4. **Given** I have an existing custom MCP server, **When** I edit its settings (name, command, or arguments), **Then** the changes are saved and reflected immediately.
5. **Given** I have multiple custom MCP servers configured, **When** I delete one, **Then** only that server is removed and others remain unaffected.

---

### User Story 3 - Connect to Connector (Priority: P0) *(Phase 1)*

As a user, I want Extremis to connect to my enabled connectors and discover available tools so that I can use them in my chat conversations.

**Why this priority**: Connection and tool discovery are essential for the connector integration to provide value.

**Implementation Phase**: Phase 1 (current focus)

**Independent Test**: Can be fully tested by enabling a connector, triggering a connection, and verifying that tools are discovered and listed.

**Acceptance Scenarios**:

1. **Given** I have enabled a connector and Extremis starts, **When** the connector is enabled, **Then** Extremis automatically connects to it in the background (non-blocking) and the status shows as "Connected".
2. **Given** a connector is connected, **When** Extremis queries for available tools, **Then** the tools provided by that connector are discovered and available for use.
3. **Given** I have configured an invalid or unreachable connector, **When** connection is attempted, **Then** I see a clear error message indicating the connection failed and why.
4. **Given** a connected connector becomes unavailable, **When** the connection is lost, **Then** Extremis auto-reconnects silently (up to 3 retries), then continues without the tool and notifies me.

---

### User Story 4 - Use Connector Tools in Chat (Priority: P0) *(Phase 1)*

As a user, I want the LLM in Extremis to be able to use tools from my connected connectors during chat conversations so that I can leverage external capabilities.

**Why this priority**: Tool usage in chat is the core value proposition - it's what makes connectors useful.

**Implementation Phase**: Phase 1 (current focus)

**Independent Test**: Can be fully tested by connecting a connector with a simple tool, asking a question in chat that would benefit from that tool, and verifying the LLM uses the tool and incorporates the result.

**Acceptance Scenarios**:

1. **Given** a connector with tools is connected, **When** I ask a question in chat that could benefit from an available tool, **Then** the LLM may choose to use that tool and incorporate the result in its response.
2. **Given** the LLM decides to use a connector tool, **When** the tool is executed, **Then** I see an inline indicator in the chat (e.g., "Using tool: [tool name]...") showing the tool is being used.
3. **Given** a tool execution returns results, **When** the response is displayed, **Then** the LLM's answer incorporates the tool results naturally.
4. **Given** a tool execution fails, **When** the error occurs, **Then** the LLM handles it gracefully and may inform me of the issue without crashing.

---

### User Story 5 - Manage Multiple Connectors (Priority: P1) *(Phase 1)*

As a power user, I want to use multiple connectors simultaneously so that I can access diverse sets of tools from different sources.

**Why this priority**: Multi-connector support extends the utility and is important for power users.

**Implementation Phase**: Phase 1 (current focus)

**Independent Test**: Can be fully tested by enabling multiple connectors and verifying tools from all are available in chat.

**Acceptance Scenarios**:

1. **Given** I have multiple connectors enabled, **When** I view the Connectors settings, **Then** I see all connectors listed with their individual connection statuses.
2. **Given** multiple connectors are connected, **When** the LLM needs a tool, **Then** it can access tools from any connected connector.
3. **Given** multiple connectors have tools with similar names, **When** tools are presented to the LLM, **Then** they are disambiguated using underscore prefix format (e.g., `filesystem_read_file`, `another_read_file`).

---

### User Story 6 - Enable/Disable Connectors (Priority: P1) *(Phase 1)*

As a user, I want to enable or disable individual connectors without removing their configurations so that I can temporarily stop using certain connectors.

**Why this priority**: This provides convenience for managing connectors and is essential for good UX.

**Implementation Phase**: Phase 1 (current focus)

**Independent Test**: Can be fully tested by disabling a connector and verifying its tools are no longer available, then re-enabling and verifying tools return.

**Acceptance Scenarios**:

1. **Given** I have a connected connector, **When** I disable it, **Then** it disconnects and its tools are no longer available in chat.
2. **Given** I have a disabled connector, **When** I enable it, **Then** it reconnects and its tools become available again.
3. **Given** a connector is disabled, **When** I view Connectors settings, **Then** the connector shows as disabled but its configuration is preserved.

---

### Edge Cases

- What happens when a connector takes too long to respond? (30 second timeout with appropriate error message)
- How does the system handle a connector that provides malformed tool definitions? (Log warning, skip invalid tools, continue with valid ones)
- What happens when a tool execution returns an unexpectedly large result? (Truncate or summarize for display, provide full data to LLM)
- How does the system behave when no connectors are enabled? (Normal chat functionality without connector tools)
- What happens if a custom MCP server process crashes? (Detect disconnection, update status, allow reconnection)
- How are credentials or sensitive data in connector configurations handled? (Store securely in Keychain, not in plain text)
- What happens if a built-in connector's backend service is unavailable? (Show appropriate error, allow retry)

## Requirements *(mandatory)*

### Functional Requirements

**Built-in Connectors**
- **FR-001**: System MUST provide pre-configured built-in connectors (GitHub, Web Search, Jira, etc.).
- **FR-002**: System MUST allow users to enable built-in connectors with minimal configuration (typically just authentication).
- **FR-003**: System MUST persist built-in connector enabled/disabled state across app restarts.

**Custom MCP Servers**
- **FR-004**: System MUST allow users to add custom MCP server configurations with a name and command (for local servers) or URL (for remote servers).
- **FR-005**: System MUST persist custom MCP server configurations across app restarts.
- **FR-006**: System MUST allow users to edit existing custom MCP server configurations.
- **FR-007**: System MUST allow users to delete custom MCP server configurations.
- **FR-008**: System MUST support both local MCP servers (via stdio/command) and remote MCP servers (via HTTP/SSE).

**Connection & Discovery**
- **FR-009**: System MUST establish connections to enabled connectors using the Model Context Protocol.
- **FR-010**: System MUST discover and list available tools from connected connectors.
- **FR-011**: System MUST display connection status for each connector (connected, disconnected, connecting, error).

**Tool Execution**
- **FR-012**: System MUST provide discovered tools to the LLM during chat conversations.
- **FR-013**: System MUST execute tool calls requested by the LLM against the appropriate connector.
- **FR-014**: System MUST return tool execution results to the LLM for incorporation into responses.
- **FR-015**: System MUST handle tool execution errors gracefully without crashing.
- **FR-016**: System MUST display an inline indicator in chat when connector tools are being executed.

**Management**
- **FR-017**: System MUST allow users to enable or disable individual connectors.
- **FR-018**: System MUST support multiple simultaneous connector connections.
- **FR-019**: System MUST display appropriate error messages when connector connections fail.

### Key Entities

- **Connector**: Abstract representation of a tool provider - can be a built-in connector or custom MCP server.
- **BuiltInConnector**: Pre-configured connector with known configuration - users only need to authenticate/enable.
- **CustomMCPServer**: User-configured MCP server - includes name, type (local/remote), command or URL, arguments, and enabled state.
- **ConnectorConnection**: Active connection to a connector - tracks connection state, discovered tools, and handles communication.
- **ConnectorTool**: Tool discovered from a connector - includes name, description, input schema, and reference to source connector.
- **ToolCall**: Request from the LLM to execute a tool - includes tool name, arguments, and associated conversation context.
- **ToolResult**: Result of a tool execution - includes success/failure status, result data, and any error information.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can enable a built-in connector in under 30 seconds (excluding external auth time).
- **SC-002**: Users can add, edit, and delete custom MCP server configurations in under 1 minute.
- **SC-003**: Connector connections are established within 5 seconds of app startup or manual connection trigger.
- **SC-004**: Tool discovery completes within 3 seconds of successful connector connection.
- **SC-005**: Tool execution results are returned to the chat within 10 seconds for typical operations.
- **SC-006**: Users can identify the connection status of any connector at a glance.
- **SC-007**: When a connector becomes unavailable, users are notified within 30 seconds.
- **SC-008**: 95% of valid connector configurations successfully connect on first attempt.
- **SC-009**: Chat functionality remains fully operational when no connectors are enabled.

## Clarifications

### Session 2026-01-18

- Q: How should Extremis handle connector connections at app startup? → A: Auto-connect all enabled connectors in background (non-blocking)
- Q: What should be the default timeout for tool execution? → A: 30 seconds
- Q: How should tool usage be visually indicated during chat? → A: Inline indicator (e.g., "Using tool: [tool name]..." message)
- Q: Should MCP servers be called "MCP Servers" in the UI? → A: No, use "Connectors" terminology. Built-in connectors and custom MCP servers appear in the same unified "Connectors" preferences tab.

## Assumptions

- Users have access to connectors they want to use (either built-in with credentials or custom MCP servers installed).
- MCP servers follow the Model Context Protocol specification for tool discovery and execution.
- The existing LLM providers (OpenAI, Anthropic, etc.) support function/tool calling in their APIs.
- Local MCP servers are executable commands available in the system PATH or specified as full paths.
- Network connectivity is available for remote connectors.
- Built-in connector backend services are generally available and reliable.
