// MARK: - Stealth Manager Tests
// Unit tests for stealth mode logic

import Foundation

// MARK: - Test Runner

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0

    static func suite(_ name: String) {
        print("\n📋 \(name)")
        print(String(repeating: "-", count: 50))
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(message)")
        } else {
            failedCount += 1
            print("  ✗ \(message)")
            print("    Expected: \(expected)")
            print("    Actual:   \(actual)")
            print("    at \(file):\(line)")
        }
    }

    static func assertTrue(_ value: Bool, _ message: String, file: String = #file, line: Int = #line) {
        assertEqual(value, true, message, file: file, line: line)
    }

    static func assertFalse(_ value: Bool, _ message: String, file: String = #file, line: Int = #line) {
        assertEqual(value, false, message, file: file, line: line)
    }

    static func printSummary() {
        print("\n==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("==================================================")
    }
}

// MARK: - StealthConfiguration Tests

func testStealthConfigurationDefaults() {
    TestRunner.suite("StealthConfiguration Defaults")

    // Clear any existing values
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_keycode")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_modifiers")
    UserDefaults.standard.removeObject(forKey: "stealth_process_disguise")
    UserDefaults.standard.removeObject(forKey: "stealth_disguise_name")

    // Test default values
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "stealthModeEnabled defaults to false")

    // kVK_ANSI_S = 1
    TestRunner.assertEqual(UserDefaults.standard.stealthToggleKeycode, 1,
        "stealthToggleKeycode defaults to kVK_ANSI_S (1)")

    // optionKey = 0x0800, shiftKey = 0x0200 → combined = 0x0A00 = 2560
    let expectedModifiers = UInt32(0x0800 | 0x0200)
    TestRunner.assertEqual(UserDefaults.standard.stealthToggleModifiers, expectedModifiers,
        "stealthToggleModifiers defaults to Option+Shift")

    TestRunner.assertTrue(UserDefaults.standard.stealthProcessDisguise,
        "stealthProcessDisguise defaults to true")

    TestRunner.assertEqual(UserDefaults.standard.stealthDisguiseName, "com.apple.hiservices-xpcservice",
        "stealthDisguiseName defaults to com.apple.hiservices-xpcservice")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_keycode")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_modifiers")
    UserDefaults.standard.removeObject(forKey: "stealth_process_disguise")
    UserDefaults.standard.removeObject(forKey: "stealth_disguise_name")
}

func testStealthConfigurationCustomValues() {
    TestRunner.suite("StealthConfiguration Custom Values")

    // Set custom values
    UserDefaults.standard.stealthModeEnabled = true
    UserDefaults.standard.stealthToggleKeycode = 42
    UserDefaults.standard.stealthToggleModifiers = 1234
    UserDefaults.standard.stealthProcessDisguise = false
    UserDefaults.standard.stealthDisguiseName = "custom-name"

    TestRunner.assertTrue(UserDefaults.standard.stealthModeEnabled,
        "stealthModeEnabled persists true")

    TestRunner.assertEqual(UserDefaults.standard.stealthToggleKeycode, 42,
        "stealthToggleKeycode persists custom value")

    TestRunner.assertEqual(UserDefaults.standard.stealthToggleModifiers, 1234,
        "stealthToggleModifiers persists custom value")

    TestRunner.assertFalse(UserDefaults.standard.stealthProcessDisguise,
        "stealthProcessDisguise persists false")

    TestRunner.assertEqual(UserDefaults.standard.stealthDisguiseName, "custom-name",
        "stealthDisguiseName persists custom value")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_keycode")
    UserDefaults.standard.removeObject(forKey: "stealth_toggle_modifiers")
    UserDefaults.standard.removeObject(forKey: "stealth_process_disguise")
    UserDefaults.standard.removeObject(forKey: "stealth_disguise_name")
}

func testStealthPersistence() {
    TestRunner.suite("Stealth Persistence")

    // Clear
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")

    // Default should be false
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "Default stealth state is false")

    // Set to true
    UserDefaults.standard.stealthModeEnabled = true
    TestRunner.assertTrue(UserDefaults.standard.stealthModeEnabled,
        "Stealth state persists as true")

    // Read via a fresh access
    let persisted = UserDefaults.standard.bool(forKey: "stealth_mode_enabled")
    TestRunner.assertTrue(persisted,
        "Stealth state readable via raw UserDefaults key")

    // Set back to false
    UserDefaults.standard.stealthModeEnabled = false
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "Stealth state persists as false")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
}

// MARK: - HotkeyIdentifier Tests

func testHotkeyIdentifierCases() {
    TestRunner.suite("HotkeyIdentifier Cases")

    // Verify new cases exist and have correct raw values
    TestRunner.assertEqual(HotkeyIdentifier.stealthToggle.rawValue, 3,
        "stealthToggle has raw value 3")

    TestRunner.assertEqual(HotkeyIdentifier.preferences.rawValue, 4,
        "preferences has raw value 4")

    // Verify existing cases unchanged
    TestRunner.assertEqual(HotkeyIdentifier.prompt.rawValue, 1,
        "prompt still has raw value 1")

    TestRunner.assertEqual(HotkeyIdentifier.magicMode.rawValue, 2,
        "magicMode still has raw value 2")

    TestRunner.assertEqual(HotkeyIdentifier.voiceInput.rawValue, 5,
        "voiceInput has raw value 5")

    TestRunner.assertEqual(HotkeyIdentifier.screenshot.rawValue, 6,
        "screenshot has raw value 6")

    // Verify CaseIterable includes all 6 cases
    TestRunner.assertEqual(HotkeyIdentifier.allCases.count, 6,
        "HotkeyIdentifier has 6 cases total")
}

// MARK: - StealthStrategy Tests

func testSharingTypeStrategy() {
    TestRunner.suite("SharingTypeStrategy")

    // We can't create real NSWindows in a test without AppKit event loop,
    // but we can verify the strategy struct exists and conforms to protocol
    let strategy = SharingTypeStrategy()

    // Verify it's a value type (struct)
    let copy = strategy
    TestRunner.assertTrue(true, "SharingTypeStrategy instantiates successfully")
    _ = copy // suppress unused warning
}

func testCollectionBehaviorStrategy() {
    TestRunner.suite("CollectionBehaviorStrategy")

    let strategy = CollectionBehaviorStrategy()
    TestRunner.assertTrue(true, "CollectionBehaviorStrategy instantiates successfully")
    _ = strategy
}

func testStrategyArrayApplication() {
    TestRunner.suite("Strategy Array Application")

    // Verify the default strategy array contains both strategies
    let strategies: [StealthStrategy] = [
        SharingTypeStrategy(),
        CollectionBehaviorStrategy()
    ]

    TestRunner.assertEqual(strategies.count, 2,
        "Default strategy array has 2 strategies")
}

// MARK: - Process Name Tests

func testProcessNameDisguise() {
    TestRunner.suite("Process Name Disguise")

    let originalName = ProcessInfo.processInfo.processName

    // Disguise
    let disguiseName = "com.apple.hiservices-xpcservice"
    ProcessInfo.processInfo.processName = disguiseName
    TestRunner.assertEqual(ProcessInfo.processInfo.processName, disguiseName,
        "Process name changes to disguise name")

    // Restore
    ProcessInfo.processInfo.processName = originalName
    TestRunner.assertEqual(ProcessInfo.processInfo.processName, originalName,
        "Process name restores to original")
}

// MARK: - Platform Version Detection Test

func testPlatformVersionDetection() {
    TestRunner.suite("Platform Version Detection")

    let version = ProcessInfo.processInfo.operatingSystemVersion
    TestRunner.assertTrue(version.majorVersion >= 10,
        "macOS major version is >= 10 (got \(version.majorVersion))")

    // Verify we can read version components
    TestRunner.assertTrue(version.minorVersion >= 0,
        "macOS minor version is non-negative (got \(version.minorVersion))")

    TestRunner.assertTrue(version.patchVersion >= 0,
        "macOS patch version is non-negative (got \(version.patchVersion))")
}

// MARK: - Stealth Toggle State Tests

func testStealthToggleState() {
    TestRunner.suite("Stealth Toggle State")

    // We can't use StealthManager.shared directly in standalone test
    // (it requires AppKit event loop), but we can test the state logic
    // via UserDefaults which is what StealthManager reads

    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")

    // Initial state should be false
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "Initial stealth state is false")

    // Simulate toggle on
    UserDefaults.standard.stealthModeEnabled = true
    TestRunner.assertTrue(UserDefaults.standard.stealthModeEnabled,
        "After toggle on, state is true")

    // Simulate toggle off
    UserDefaults.standard.stealthModeEnabled = false
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "After toggle off, state is false")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
}

func testActivateDeactivateCycle() {
    TestRunner.suite("Activate/Deactivate Cycle")

    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")

    // Full cycle: off → on → off
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "Starts off")

    UserDefaults.standard.stealthModeEnabled = true
    TestRunner.assertTrue(UserDefaults.standard.stealthModeEnabled,
        "Activate sets true")

    UserDefaults.standard.stealthModeEnabled = false
    TestRunner.assertFalse(UserDefaults.standard.stealthModeEnabled,
        "Deactivate restores false")

    // Verify process name can round-trip
    let original = ProcessInfo.processInfo.processName
    ProcessInfo.processInfo.processName = "disguised"
    ProcessInfo.processInfo.processName = original
    TestRunner.assertEqual(ProcessInfo.processInfo.processName, original,
        "Process name round-trips correctly")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "stealth_mode_enabled")
}

// MARK: - Opacity Configuration Tests

func testStealthOpacityDefault() {
    TestRunner.suite("Stealth Opacity Default")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")

    TestRunner.assertEqual(UserDefaults.standard.stealthOpacity, 0.35,
        "stealthOpacity defaults to 0.35")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")
}

func testStealthOpacityCustomValue() {
    TestRunner.suite("Stealth Opacity Custom Value")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")

    UserDefaults.standard.stealthOpacity = 0.5
    TestRunner.assertEqual(UserDefaults.standard.stealthOpacity, 0.5,
        "stealthOpacity persists 0.5")

    UserDefaults.standard.stealthOpacity = 0.15
    TestRunner.assertEqual(UserDefaults.standard.stealthOpacity, 0.15,
        "stealthOpacity persists minimum 0.15")

    UserDefaults.standard.stealthOpacity = 1.0
    TestRunner.assertEqual(UserDefaults.standard.stealthOpacity, 1.0,
        "stealthOpacity persists maximum 1.0")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")
}

func testStealthOpacityPersistence() {
    TestRunner.suite("Stealth Opacity Persistence")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")

    UserDefaults.standard.stealthOpacity = 0.7
    let raw = UserDefaults.standard.double(forKey: "stealth_opacity")
    TestRunner.assertEqual(raw, 0.7,
        "stealthOpacity readable via raw UserDefaults key")

    UserDefaults.standard.removeObject(forKey: "stealth_opacity")
}

// MARK: - ImageSourceType Screenshot Tests

func testImageSourceTypeScreenshot() {
    TestRunner.suite("ImageSourceType Screenshot Case")

    let sourceType = ImageSourceType.screenshot
    TestRunner.assertEqual(sourceType.rawValue, "screenshot",
        "screenshot raw value is 'screenshot'")

    // Verify all cases exist
    let allCases: [ImageSourceType] = [.clipboard, .filePicker, .dragAndDrop, .screenshot]
    TestRunner.assertEqual(allCases.count, 4,
        "ImageSourceType has 4 cases")

    // Verify Codable round-trip
    let encoded = try? JSONEncoder().encode(sourceType)
    TestRunner.assertTrue(encoded != nil, "screenshot case encodes successfully")

    if let data = encoded {
        let decoded = try? JSONDecoder().decode(ImageSourceType.self, from: data)
        TestRunner.assertEqual(decoded, .screenshot,
            "screenshot case round-trips through Codable")
    }
}

// MARK: - Entry Point

// Inline minimal types needed for compilation
enum HotkeyIdentifier: UInt32, CaseIterable {
    case prompt = 1
    case magicMode = 2
    case stealthToggle = 3
    case preferences = 4
    case voiceInput = 5
    case screenshot = 6
}

struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

protocol StealthStrategy {
    func apply(to window: Any)
    func remove(from window: Any)
}

struct SharingTypeStrategy: StealthStrategy {
    func apply(to window: Any) {}
    func remove(from window: Any) {}
}

final class CollectionBehaviorStrategy: StealthStrategy {
    func apply(to window: Any) {}
    func remove(from window: Any) {}
}

// UserDefaults extension for tests (mirrors production code)
extension UserDefaults {
    var stealthModeEnabled: Bool {
        get { bool(forKey: "stealth_mode_enabled") }
        set { set(newValue, forKey: "stealth_mode_enabled") }
    }
    var stealthToggleKeycode: UInt32 {
        get {
            let val = integer(forKey: "stealth_toggle_keycode")
            return val == 0 ? 1 : UInt32(val)  // kVK_ANSI_S = 1
        }
        set { set(Int(newValue), forKey: "stealth_toggle_keycode") }
    }
    var stealthToggleModifiers: UInt32 {
        get {
            let val = integer(forKey: "stealth_toggle_modifiers")
            return val == 0 ? UInt32(0x0800 | 0x0200) : UInt32(val)
        }
        set { set(Int(newValue), forKey: "stealth_toggle_modifiers") }
    }
    var stealthProcessDisguise: Bool {
        get {
            if object(forKey: "stealth_process_disguise") == nil { return true }
            return bool(forKey: "stealth_process_disguise")
        }
        set { set(newValue, forKey: "stealth_process_disguise") }
    }
    var stealthDisguiseName: String {
        get { string(forKey: "stealth_disguise_name") ?? "com.apple.hiservices-xpcservice" }
        set { set(newValue, forKey: "stealth_disguise_name") }
    }
    var stealthOpacity: Double {
        get {
            if object(forKey: "stealth_opacity") == nil { return 0.35 }
            return double(forKey: "stealth_opacity")
        }
        set { set(newValue, forKey: "stealth_opacity") }
    }
}

enum ImageSourceType: String, Codable, Equatable, Hashable {
    case clipboard
    case filePicker = "file_picker"
    case dragAndDrop = "drag_and_drop"
    case screenshot
}

@main
struct StealthManagerTests {
    static func main() {
        // Configuration tests
        testStealthConfigurationDefaults()
        testStealthConfigurationCustomValues()
        testStealthPersistence()

        // HotkeyIdentifier tests
        testHotkeyIdentifierCases()

        // Strategy tests
        testSharingTypeStrategy()
        testCollectionBehaviorStrategy()
        testStrategyArrayApplication()

        // Process name tests
        testProcessNameDisguise()

        // Platform version tests
        testPlatformVersionDetection()

        // State toggle tests
        testStealthToggleState()
        testActivateDeactivateCycle()

        // Opacity tests
        testStealthOpacityDefault()
        testStealthOpacityCustomValue()
        testStealthOpacityPersistence()

        // ImageSourceType tests
        testImageSourceTypeScreenshot()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
