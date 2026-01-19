# Quickstart: Connectors

**Feature**: Connectors (MCP Support)
**Date**: 2026-01-18

## Overview

Connectors enable Extremis to integrate with external tools and services. This guide explains how to set up and use connectors once the feature is implemented.

**Two types of connectors**:
1. **Built-in Connectors** - Pre-configured integrations (GitHub, Web Search, Jira) with one-click setup
2. **Custom MCP Servers** - User-configured servers for advanced use cases

---

## Prerequisites

1. **Extremis** installed and running
2. **LLM Provider** configured that supports tool calling (OpenAI, Anthropic)
3. **Credentials** for connectors you want to use (API keys, tokens, etc.)

---

## Enabling Built-in Connectors

Built-in connectors are the easiest way to extend Extremis with external tools.

### Via Preferences UI

1. Open Extremis Preferences (⌘,)
2. Navigate to **Connectors** tab
3. In the **Built-in Connectors** section, find the connector you want
4. Click **Connect**
5. Follow the authentication prompts (enter API key, token, etc.)
6. The connector shows "Connected" when ready

### Available Built-in Connectors

| Connector | What It Does | Auth Required |
|-----------|-------------|---------------|
| **GitHub** | Search repos, manage issues and PRs | Personal Access Token |
| **Brave Search** | Search the web for current information | API Key |
| **Jira** | Manage Jira issues and projects | API Token + Instance URL |

### Example: Enabling GitHub

1. Open **Preferences** → **Connectors**
2. Click **Connect** next to GitHub
3. Enter your GitHub Personal Access Token
   - Get one at: GitHub → Settings → Developer settings → Personal access tokens
   - Required scopes: `repo`, `read:user`
4. Click **Save**
5. GitHub shows as "Connected" with available tools

---

## Adding Custom MCP Servers

For advanced use cases, you can connect to any MCP-compatible server.

### Via Preferences UI

1. Open **Preferences** → **Connectors**
2. In the **Custom MCP Servers** section, click **+ Add New**
3. Configure the server:
   - **Name**: A friendly display name
   - **Type**: Local (STDIO) or Remote (HTTP)
   - **Command/URL**: Path to executable or server URL
   - **Arguments**: Command line args (local only)
   - **Environment**: Environment variables (local only)
4. Click **Save**
5. Toggle **Enabled** to connect

### Via Configuration File

Edit `~/Library/Application Support/Extremis/connectors.json`:

```json
{
  "version": 1,
  "builtIn": {
    "github": { "enabled": true }
  },
  "custom": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Filesystem Tools",
      "type": "stdio",
      "enabled": true,
      "transport": {
        "stdio": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/projects"],
          "env": {}
        }
      }
    }
  ]
}
```

> **Note**: API keys are stored in Keychain, not in this config file. Enter them via the Preferences UI.

Restart Extremis or click **Reload Config** in Preferences.

---

## Using Connector Tools in Chat

Once connectors are enabled, their tools are automatically available to the LLM during chat.

### Example Conversation

**You**: What open issues do I have in the extremis repo?

**Extremis**: *Using tool: GitHub: search_issues...*

You have 5 open issues in the extremis repository:
1. #42 - Add dark mode support
2. #38 - Improve error messages
3. ...

### Tool Indicators

During tool execution, you'll see inline indicators:
- **Using tool: [connector]: [name]...** - Tool is executing
- **Tool completed** - Execution finished (click to expand details)
- **Tool failed** - Error occurred (with retry option)

### Multiple Tools

The LLM can use multiple tools from different connectors in a single response:

**You**: Search GitHub for "auth" issues and find related articles online

**Extremis**:
*Using tool: GitHub: search_issues...*
*Using tool: Web Search: search...*

I found 3 GitHub issues related to authentication and some helpful articles...

---

## Managing Connectors

### Connection Status

In the Connectors preferences tab, each connector shows its status:
- 🟢 **Connected** - Connector is active and tools are available
- 🟡 **Connecting** - Connection in progress
- ⚪ **Disconnected** - Connector is not connected
- 🔴 **Error** - Connection failed (hover for details)

### Enable/Disable

Toggle the **Enabled** switch to connect or disconnect a connector without removing its configuration.

### Test Connection

Click **Test** to verify a connector configuration before enabling it.

### Disconnect

For built-in connectors, click **Disconnect** to remove credentials and disable the connector.

For custom MCP servers, you can disable or delete them entirely.

---

## Common MCP Server Examples

### Filesystem Server
Access local files and directories.

```json
{
  "name": "Filesystem",
  "type": "stdio",
  "transport": {
    "stdio": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
      "env": {}
    }
  }
}
```

### Brave Search Server
Search the web using Brave Search API.

```json
{
  "name": "Brave Search",
  "type": "stdio",
  "transport": {
    "stdio": {
      "command": "npx",
      "args": ["-y", "@anthropics/brave-search-mcp"],
      "env": {}
    }
  }
}
```

> **Note**: The `BRAVE_API_KEY` is entered in the Preferences UI and stored securely in Keychain, not in the config file.

### Custom HTTP Server

```json
{
  "name": "My Custom API",
  "type": "http",
  "transport": {
    "http": {
      "url": "https://my-mcp-server.example.com/mcp",
      "headers": {}
    }
  }
}
```

> **Note**: For sensitive tokens and API keys, Extremis stores them securely in the macOS Keychain rather than in the config file.

---

## Troubleshooting

### Connector Won't Connect

1. **Check credentials**: Ensure API keys/tokens are correct
2. **Check command path**: For local servers, ensure the command is accessible
   ```bash
   which npx  # Should return a path
   ```
3. **Test manually**: Try running the server command in Terminal
   ```bash
   npx -y @modelcontextprotocol/server-filesystem /tmp
   ```
4. **Check permissions**: Extremis needs accessibility permissions

### Tools Not Appearing

1. **Verify connection**: Check connector status is "Connected"
2. **Wait for discovery**: Tools are discovered after connection (up to 3s)
3. **Check server logs**: Some servers log to stderr

### Tool Execution Fails

1. **Check arguments**: Ensure you're providing required inputs
2. **Timeout**: Default is 30 seconds; some operations may need more time
3. **Server error**: Check server logs for details
4. **Auth expired**: Re-authenticate the connector

### Built-in Connector Issues

1. **GitHub**: Ensure token has required scopes (`repo`, `read:user`)
2. **Web Search**: Verify API key is active
3. **Jira**: Check instance URL is correct and accessible

---

## Configuration File Location

```
~/Library/Application Support/Extremis/connectors.json
```

Backup this file to preserve your connector configurations. Note that credentials are stored separately in the macOS Keychain.

---

## Security Notes

- **Credentials**: API keys and tokens are stored in macOS Keychain, not in the config file
- **Local servers**: Run as separate processes with limited permissions
- **Remote servers**: Only HTTPS connections are supported
- **Config file**: Can be safely shared (contains no secrets)

---

## Next Steps

- Enable the built-in connectors you need
- Explore available MCP servers at [MCP Server List](https://modelcontextprotocol.io/servers)
- Build your own MCP server using the [MCP SDK](https://github.com/modelcontextprotocol/swift-sdk)
- Configure multiple connectors for different workflows
