// MARK: - Instruction Model Tests

import XCTest
@testable import Extremis

final class InstructionTests: XCTestCase {
    
    // MARK: - Creation Tests
    
    func testInstructionCreation() {
        let contextId = UUID()
        let instruction = Instruction(
            text: "Write a professional reply",
            contextId: contextId
        )
        
        XCTAssertEqual(instruction.text, "Write a professional reply")
        XCTAssertEqual(instruction.contextId, contextId)
        XCTAssertNotNil(instruction.id)
    }
    
    // MARK: - Validation Tests
    
    func testValidInstruction() {
        let instruction = Instruction(
            text: "Help me write this email",
            contextId: UUID()
        )
        
        XCTAssertTrue(instruction.isValid)
    }
    
    func testEmptyInstructionIsInvalid() {
        let instruction = Instruction(
            text: "",
            contextId: UUID()
        )
        
        XCTAssertFalse(instruction.isValid)
    }
    
    func testWhitespaceOnlyInstructionIsInvalid() {
        let instruction = Instruction(
            text: "   \n\t  ",
            contextId: UUID()
        )
        
        XCTAssertFalse(instruction.isValid)
    }
    
    func testTooLongInstructionIsInvalid() {
        let longText = String(repeating: "a", count: Instruction.maxLength + 1)
        let instruction = Instruction(
            text: longText,
            contextId: UUID()
        )
        
        XCTAssertFalse(instruction.isValid)
    }
    
    func testMaxLengthInstructionIsValid() {
        let maxText = String(repeating: "a", count: Instruction.maxLength)
        let instruction = Instruction(
            text: maxText,
            contextId: UUID()
        )
        
        XCTAssertTrue(instruction.isValid)
    }
    
    // MARK: - Trimming Tests
    
    func testTrimmedInstruction() {
        let instruction = Instruction(
            text: "  Hello world  \n",
            contextId: UUID()
        )
        
        let trimmed = instruction.trimmed
        
        XCTAssertEqual(trimmed.text, "Hello world")
        XCTAssertEqual(trimmed.id, instruction.id)
        XCTAssertEqual(trimmed.contextId, instruction.contextId)
    }
    
    // MARK: - Codable Tests
    
    func testInstructionCodable() throws {
        let instruction = Instruction(
            text: "Test instruction",
            contextId: UUID()
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(instruction)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Instruction.self, from: data)
        
        XCTAssertEqual(instruction.id, decoded.id)
        XCTAssertEqual(instruction.text, decoded.text)
        XCTAssertEqual(instruction.contextId, decoded.contextId)
    }
}

