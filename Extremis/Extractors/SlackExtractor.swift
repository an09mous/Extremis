// MARK: - Slack Context Extractor
// Extracts context from Slack desktop app and web

import Foundation
import AppKit
import ApplicationServices

/// Extracts context from Slack (desktop app or web)
final class SlackExtractor: ContextExtractor {
    
    // MARK: - Properties
    
    private let browserBridge = BrowserBridge.shared
    
    // MARK: - ContextExtractor Protocol
    
    var identifier: String { "slack" }
    var displayName: String { "Slack Extractor" }
    var supportedBundleIdentifiers: [String] { ["com.tinyspeck.slackmacgap"] }
    var supportedURLPatterns: [String] { ["app.slack.com", "*.slack.com"] }
    
    func canExtract(from source: ContextSource) -> Bool {
        // Check desktop app by bundle identifier (most reliable)
        if supportedBundleIdentifiers.contains(source.bundleIdentifier) {
            return true
        }
        // Check web URL for Slack web app
        if let url = source.url?.host {
            return url.contains("slack.com")
        }
        // Note: We intentionally don't check window title because other apps
        // (like VS Code editing Slack-related files) might have "Slack" in the title
        return false
    }
    
    func extract() async throws -> Context {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ContextExtractionError.unknown("No frontmost application")
        }
        
        let isDesktopApp = app.bundleIdentifier == "com.tinyspeck.slackmacgap"
        
        if isDesktopApp {
            return try await extractFromDesktopApp(app)
        } else {
            return try await extractFromWeb(app)
        }
    }
    
    // MARK: - Desktop App Extraction (AX APIs)

    private func extractFromDesktopApp(_ app: NSRunningApplication) async throws -> Context {
        print("🔍 SlackExtractor: Extracting from DESKTOP app...")

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get window title to determine channel
        let windowTitle = getWindowTitle(appElement)
        print("🔍 SlackExtractor: Window title = \(windowTitle ?? "nil")")

        let channelInfo = parseChannelFromTitle(windowTitle)
        print("🔍 SlackExtractor: Channel = \(channelInfo.name ?? "nil"), type = \(channelInfo.type)")

        // Get selected/focused text first
        let selectedText = getSelectedText(appElement)
        print("🔍 SlackExtractor: Selected text via AX = \(selectedText ?? "nil")")

        // Capture text around cursor using common method
        let (precedingText, succeedingText) = captureTextAroundCursor(verbose: true)

        // Parse messages from captured content (use preceding text for context)
        var extractedMessages: [SlackMessage] = []
        var extractedParticipants: [String] = []

        if let content = precedingText, !content.isEmpty {
            let parsed = parseSlackContent(content)
            extractedMessages = parsed.messages
            extractedParticipants = parsed.participants
            print("🔍 SlackExtractor: Parsed \(extractedMessages.count) messages from clipboard content")
        }

        let source = ContextSource(
            applicationName: "Slack",
            bundleIdentifier: app.bundleIdentifier ?? "com.tinyspeck.slackmacgap",
            windowTitle: windowTitle
        )

        let metadata = SlackMetadata(
            channelName: channelInfo.name,
            channelType: channelInfo.type,
            participants: extractedParticipants,
            recentMessages: extractedMessages
        )

        return Context(
            source: source,
            selectedText: selectedText,
            precedingText: precedingText,
            succeedingText: succeedingText,
            metadata: .slack(metadata)
        )
    }

    // MARK: - Content Parsing

    /// Parse Slack content to extract messages and participants
    private func parseSlackContent(_ content: String) -> (messages: [SlackMessage], participants: [String]) {
        var messages: [SlackMessage] = []
        var participants: Set<String> = []

        let lines = content.components(separatedBy: .newlines)
        var currentSender: String?
        var currentMessage: String = ""

        // Common Slack message patterns:
        // "Name  HH:MM AM/PM" or "Name  Yesterday at HH:MM" followed by message
        // Or just "Name" on one line, message on next

        let timestampPattern = try? NSRegularExpression(
            pattern: "^([A-Za-z][A-Za-z0-9 _.-]*)\\s{2,}(\\d{1,2}:\\d{2}\\s*(?:AM|PM)?|Yesterday|Today|\\d{1,2}/\\d{1,2}/\\d{2,4})",
            options: .caseInsensitive
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip UI elements
            let skipPatterns = ["New message", "Jump to", "Add bookmark", "Search",
                               "Threads", "Direct messages", "Channels", "Apps",
                               "replied to a thread", "joined the channel", "left the channel",
                               "Add a reaction", "Start a thread", "Share message"]
            if skipPatterns.contains(where: { trimmed.contains($0) }) {
                continue
            }

            // Check if this is a sender line with timestamp
            if let regex = timestampPattern,
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                // Save previous message
                if let sender = currentSender, !currentMessage.isEmpty {
                    messages.append(SlackMessage(sender: sender, content: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines), timestamp: Date()))
                    participants.insert(sender)
                }

                // Start new message
                if let senderRange = Range(match.range(at: 1), in: trimmed) {
                    currentSender = String(trimmed[senderRange]).trimmingCharacters(in: .whitespaces)
                }
                currentMessage = ""
            } else if currentSender != nil {
                // Continuation of current message
                if !currentMessage.isEmpty {
                    currentMessage += "\n"
                }
                currentMessage += trimmed
            }
        }

        // Don't forget the last message
        if let sender = currentSender, !currentMessage.isEmpty {
            messages.append(SlackMessage(sender: sender, content: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines), timestamp: Date()))
            participants.insert(sender)
        }

        print("🔍 SlackExtractor: parseSlackContent found \(messages.count) messages, \(participants.count) participants")

        return (messages, Array(participants))
    }

    /// Print the complete AX tree for debugging
    private func printAXTree(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth < maxDepth else {
            if depth == maxDepth {
                print("\(indent(depth))... (max depth reached)")
            }
            return
        }

        // Get role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "Unknown"

        // Get subrole
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String

        // Get title
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String

        // Get value
        var valueValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueValue)
        let value = valueValue as? String

        // Get description
        var descValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        let desc = descValue as? String

        // Get role description
        var roleDescValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
        let roleDesc = roleDescValue as? String

        // Get identifier (if available)
        var identifierValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifierValue)
        let identifier = identifierValue as? String

        // Build output line
        var line = "\(indent(depth))[\(role)]"
        if let sr = subrole { line += " subrole=\(sr)" }
        if let id = identifier { line += " id=\"\(id)\"" }
        if let t = title, !t.isEmpty { line += " title=\"\(t.prefix(50))\(t.count > 50 ? "..." : "")\"" }
        if let rd = roleDesc, !rd.isEmpty && rd != role { line += " roleDesc=\"\(rd)\"" }
        if let d = desc, !d.isEmpty { line += " desc=\"\(d.prefix(50))\(d.count > 50 ? "..." : "")\"" }
        if let v = value, !v.isEmpty {
            let preview = v.replacingOccurrences(of: "\n", with: "\\n").prefix(80)
            line += " value=\"\(preview)\(v.count > 80 ? "..." : "")\""
        }

        print(line)

        // Get children
        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if let children = childrenValue as? [AXUIElement] {
            let childCount = children.count
            if childCount > 0 {
                // Limit children at deeper levels
                let limit = depth < 3 ? 30 : (depth < 6 ? 20 : 10)
                for child in children.prefix(limit) {
                    printAXTree(child, depth: depth + 1, maxDepth: maxDepth)
                }
                if childCount > limit {
                    print("\(indent(depth + 1))... (\(childCount - limit) more children)")
                }
            }
        }
    }

    private func indent(_ depth: Int) -> String {
        return String(repeating: "  ", count: depth)
    }

    /// Explore the AX hierarchy to find more context
    private func exploreAXHierarchy(_ appElement: AXUIElement) -> (participants: [String], messages: [SlackMessage]) {
        var participants: [String] = []
        var messages: [SlackMessage] = []
        var allTexts: [String] = []

        // Get focused window
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard let window = windowValue else {
            print("🔍 SlackExtractor: No focused window")
            return ([], [])
        }

        print("🔍 SlackExtractor: Starting AX hierarchy exploration...")

        // Explore children to find message list and participants
        exploreElement(window as! AXUIElement, depth: 0, maxDepth: 15,
                      allTexts: &allTexts, verbose: true)

        print("🔍 SlackExtractor: Found \(allTexts.count) text elements")

        // Process collected texts to extract messages
        // Slack messages typically have format: "sender: message" or just message text
        for text in allTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip very short or very long texts
            guard trimmed.count >= 5 && trimmed.count < 2000 else { continue }

            // Skip UI elements
            let skipPatterns = ["Search", "Home", "DMs", "Activity", "More", "New message",
                               "Threads", "Drafts", "Files", "Channels", "Add", "Join",
                               "typing", "edited", "View thread", "Reply", "reactions"]
            if skipPatterns.contains(where: { trimmed.contains($0) }) && trimmed.count < 30 {
                continue
            }

            // Check if it looks like a message with sender
            if let colonIndex = trimmed.firstIndex(of: ":"),
               colonIndex > trimmed.startIndex,
               trimmed.distance(from: trimmed.startIndex, to: colonIndex) < 30 {
                let sender = String(trimmed[..<colonIndex])
                let content = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && content.count > 3 {
                    messages.append(SlackMessage(sender: sender, content: content, timestamp: Date()))
                    if !participants.contains(sender) {
                        participants.append(sender)
                    }
                }
            } else if trimmed.count > 20 {
                // Plain text that might be a message
                messages.append(SlackMessage(sender: "Unknown", content: trimmed, timestamp: Date()))
            }
        }

        print("🔍 SlackExtractor: Extracted \(messages.count) messages, \(participants.count) participants")
        return (participants, messages)
    }

    private func exploreElement(_ element: AXUIElement, depth: Int, maxDepth: Int,
                               allTexts: inout [String], verbose: Bool) {
        guard depth < maxDepth else { return }

        // Get role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        // Get various text attributes
        var valueValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueValue)
        let value = valueValue as? String

        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String

        var descValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        let desc = descValue as? String

        var helpValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpValue)
        _ = helpValue as? String  // help attribute retrieved but not currently used

        // Collect text content
        let indent = String(repeating: "  ", count: min(depth, 5))

        if let v = value, !v.isEmpty && v.count > 3 {
            if verbose && depth < 6 {
                print("🔍 \(indent)[\(role)] value(\(v.count)): \"\(v.prefix(80))\(v.count > 80 ? "..." : "")\"")
            }
            allTexts.append(v)
        }

        if let t = title, !t.isEmpty && t.count > 3 {
            if verbose && depth < 6 {
                print("🔍 \(indent)[\(role)] title: \"\(t.prefix(80))\"")
            }
            // Don't add titles as they're usually UI labels
        }

        if let d = desc, !d.isEmpty && d.count > 10 {
            if verbose && depth < 6 {
                print("🔍 \(indent)[\(role)] desc: \"\(d.prefix(80))\"")
            }
            allTexts.append(d)
        }

        // Get children
        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if let children = childrenValue as? [AXUIElement] {
            // Process more children at shallower depths
            let limit = depth < 3 ? 50 : (depth < 6 ? 30 : 15)
            for child in children.prefix(limit) {
                exploreElement(child, depth: depth + 1, maxDepth: maxDepth,
                             allTexts: &allTexts, verbose: verbose)
            }
        }
    }
    
    // MARK: - Web Extraction (JavaScript)
    
    private func extractFromWeb(_ app: NSRunningApplication) async throws -> Context {
        let tab = browserBridge.getCurrentTab(from: app)
        
        // JavaScript to extract Slack context from DOM
        let jsScript = """
        (function() {
            var result = {};
            // Get channel name
            var channelEl = document.querySelector('[data-qa="channel_name"]') || 
                           document.querySelector('.p-channel_sidebar__channel--selected');
            result.channel = channelEl ? channelEl.textContent.trim() : null;
            
            // Get recent messages
            var messages = [];
            document.querySelectorAll('[data-qa="message_container"]').forEach(function(m, i) {
                if (i < 10) {
                    var sender = m.querySelector('[data-qa="message_sender_name"]');
                    var text = m.querySelector('[data-qa="message-text"]');
                    if (sender && text) {
                        messages.push({sender: sender.textContent, text: text.textContent});
                    }
                }
            });
            result.messages = messages;
            
            // Get selected text
            result.selectedText = window.getSelection().toString();
            
            return JSON.stringify(result);
        })()
        """
        
        let jsonResult = browserBridge.executeJavaScript(jsScript, in: app)
        let webData = parseWebResult(jsonResult)
        
        let source = ContextSource(
            applicationName: "Slack",
            bundleIdentifier: app.bundleIdentifier ?? "",
            windowTitle: tab?.title,
            url: tab?.url
        )
        
        let metadata = SlackMetadata(
            channelName: webData.channelName,
            channelType: .channel,
            participants: [],
            recentMessages: webData.messages
        )
        
        return Context(
            source: source,
            selectedText: webData.selectedText,
            metadata: .slack(metadata)
        )
    }
    
    // MARK: - Helper Methods
    
    private func getWindowTitle(_ appElement: AXUIElement) -> String? {
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard let window = windowValue else { return nil }
        
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        return titleValue as? String
    }
    
    private func parseChannelFromTitle(_ title: String?) -> (name: String?, type: SlackChannelType) {
        guard let title = title else { return (nil, .channel) }
        print("🔍 SlackExtractor: Parsing title: \(title)")

        // Format variations:
        // "#channel-name - Workspace - Slack"
        // "channel-name (Channel) - Workspace - Slack"
        // "Person Name - Workspace - Slack" (DM)
        // "Group Name (Group) - Workspace - Slack"
        // "Thread in #channel - Workspace - Slack"

        let parts = title.components(separatedBy: " - ")
        guard let channelPart = parts.first else { return (nil, .channel) }

        // Check for explicit type markers in title
        if title.contains("(Channel)") {
            let name = channelPart.replacingOccurrences(of: " (Channel)", with: "")
                                  .replacingOccurrences(of: "#", with: "")
            return (name, .channel)
        } else if title.contains("(Group)") {
            let name = channelPart.replacingOccurrences(of: " (Group)", with: "")
            return (name, .groupDM)
        } else if title.contains("Thread in") {
            let name = channelPart.replacingOccurrences(of: "Thread in ", with: "")
                                  .replacingOccurrences(of: "#", with: "")
            return (name, .thread)
        } else if channelPart.hasPrefix("#") {
            return (String(channelPart.dropFirst()), .channel)
        } else {
            // Assume DM if no channel indicator
            return (channelPart, .directMessage)
        }
    }

    private func getSelectedText(_ appElement: AXUIElement) -> String? {
        var focusedElement: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        return selectedText as? String
    }

    private func getVisibleMessages(_ appElement: AXUIElement) -> [SlackMessage] {
        // AX extraction of messages is limited - return empty for now
        // Web extraction via JS is more reliable
        return []
    }

    private func parseWebResult(_ json: String?) -> (channelName: String?, selectedText: String?, messages: [SlackMessage]) {
        guard let json = json, let data = json.data(using: .utf8) else {
            return (nil, nil, [])
        }

        do {
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let channel = dict["channel"] as? String
                let selected = dict["selectedText"] as? String
                var messages: [SlackMessage] = []

                if let msgArray = dict["messages"] as? [[String: String]] {
                    messages = msgArray.compactMap { msg in
                        guard let sender = msg["sender"], let text = msg["text"] else { return nil }
                        return SlackMessage(sender: sender, content: text, timestamp: Date())
                    }
                }

                return (channel, selected, messages)
            }
        } catch {
            print("⚠️ Failed to parse Slack web result: \(error)")
        }

        return (nil, nil, [])
    }
}

