// MARK: - Context Model Tests

import XCTest
@testable import Extremis

final class ContextTests: XCTestCase {
    
    // MARK: - Context Tests
    
    func testContextCreation() {
        let source = ContextSource(
            applicationName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap"
        )
        
        let context = Context(
            source: source,
            selectedText: "Hello world"
        )
        
        XCTAssertEqual(context.source.applicationName, "Slack")
        XCTAssertEqual(context.selectedText, "Hello world")
        XCTAssertNil(context.precedingText)
    }
    
    func testContextSourceWithURL() {
        let source = ContextSource(
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail - Inbox",
            url: URL(string: "https://mail.google.com/mail/u/0/#inbox")
        )
        
        XCTAssertEqual(source.applicationName, "Google Chrome")
        XCTAssertNotNil(source.url)
        XCTAssertEqual(source.url?.host, "mail.google.com")
    }
    
    // MARK: - Metadata Tests
    
    func testSlackMetadata() {
        let metadata = SlackMetadata(
            channelName: "#general",
            channelType: .channel,
            participants: ["Alice", "Bob"]
        )
        
        XCTAssertEqual(metadata.channelName, "#general")
        XCTAssertEqual(metadata.channelType, .channel)
        XCTAssertEqual(metadata.participants.count, 2)
    }
    
    func testGmailMetadata() {
        let metadata = GmailMetadata(
            subject: "Meeting Tomorrow",
            recipients: ["bob@example.com"],
            isReply: true
        )
        
        XCTAssertEqual(metadata.subject, "Meeting Tomorrow")
        XCTAssertTrue(metadata.isReply)
    }
    
    func testGitHubMetadata() {
        let metadata = GitHubMetadata(
            prTitle: "Add new feature",
            prNumber: 123,
            baseBranch: "main",
            headBranch: "feature/new-feature"
        )
        
        XCTAssertEqual(metadata.prNumber, 123)
        XCTAssertEqual(metadata.baseBranch, "main")
    }
    
    // MARK: - Codable Tests
    
    func testContextCodable() throws {
        let source = ContextSource(
            applicationName: "Test App",
            bundleIdentifier: "com.test.app"
        )
        
        let context = Context(
            source: source,
            selectedText: "Test text",
            metadata: .generic(GenericMetadata())
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(context)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Context.self, from: data)
        
        XCTAssertEqual(context.id, decoded.id)
        XCTAssertEqual(context.selectedText, decoded.selectedText)
    }
}

