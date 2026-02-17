// MARK: - Design System Tests
// Tests for DS design token consistency and ordering invariants

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

    static func setGroup(_ name: String) {
        currentGroup = name
        print("")
        print("📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
        }
    }

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Standalone DS Token Definitions (for testing without SwiftUI)
// These mirror the values in DesignSystem.swift but use plain CGFloat for standalone compilation

enum DSTest {
    enum Radii {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let pill: CGFloat = 20
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

struct ShadowStyleTest {
    let radius: CGFloat
    let opacity: Double
}

let shadowSubtle = ShadowStyleTest(radius: 2, opacity: 0.06)
let shadowMedium = ShadowStyleTest(radius: 6, opacity: 0.1)
let shadowElevated = ShadowStyleTest(radius: 12, opacity: 0.15)

// MARK: - Tests

func testRadiiOrdering() {
    TestRunner.setGroup("Radii Ordering")

    TestRunner.assertTrue(
        DSTest.Radii.small < DSTest.Radii.medium,
        "small < medium"
    )
    TestRunner.assertTrue(
        DSTest.Radii.medium < DSTest.Radii.large,
        "medium < large"
    )
    TestRunner.assertTrue(
        DSTest.Radii.large < DSTest.Radii.xLarge,
        "large < xLarge"
    )
    TestRunner.assertTrue(
        DSTest.Radii.xLarge < DSTest.Radii.pill,
        "xLarge < pill"
    )
}

func testRadiiValues() {
    TestRunner.setGroup("Radii Values")

    TestRunner.assertTrue(DSTest.Radii.small > 0, "small radius > 0")
    TestRunner.assertTrue(DSTest.Radii.medium > 0, "medium radius > 0")
    TestRunner.assertTrue(DSTest.Radii.large > 0, "large radius > 0")
    TestRunner.assertTrue(DSTest.Radii.xLarge > 0, "xLarge radius > 0")
    TestRunner.assertTrue(DSTest.Radii.pill > 0, "pill radius > 0")

    TestRunner.assertEqual(DSTest.Radii.small, 4, "small radius is 4")
    TestRunner.assertEqual(DSTest.Radii.medium, 8, "medium radius is 8")
    TestRunner.assertEqual(DSTest.Radii.large, 12, "large radius is 12")
    TestRunner.assertEqual(DSTest.Radii.xLarge, 16, "xLarge radius is 16")
    TestRunner.assertEqual(DSTest.Radii.pill, 20, "pill radius is 20")
}

func testSpacingOrdering() {
    TestRunner.setGroup("Spacing Ordering")

    TestRunner.assertTrue(
        DSTest.Spacing.xxs < DSTest.Spacing.xs,
        "xxs < xs"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.xs < DSTest.Spacing.sm,
        "xs < sm"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.sm < DSTest.Spacing.md,
        "sm < md"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.md < DSTest.Spacing.lg,
        "md < lg"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.lg < DSTest.Spacing.xl,
        "lg < xl"
    )
}

func testSpacingValues() {
    TestRunner.setGroup("Spacing Values")

    TestRunner.assertEqual(DSTest.Spacing.xxs, 2, "xxs spacing is 2")
    TestRunner.assertEqual(DSTest.Spacing.xs, 4, "xs spacing is 4")
    TestRunner.assertEqual(DSTest.Spacing.sm, 8, "sm spacing is 8")
    TestRunner.assertEqual(DSTest.Spacing.md, 12, "md spacing is 12")
    TestRunner.assertEqual(DSTest.Spacing.lg, 16, "lg spacing is 16")
    TestRunner.assertEqual(DSTest.Spacing.xl, 24, "xl spacing is 24")
}

func testShadowOrdering() {
    TestRunner.setGroup("Shadow Ordering")

    TestRunner.assertTrue(
        shadowSubtle.radius < shadowMedium.radius,
        "subtle shadow radius < medium shadow radius"
    )
    TestRunner.assertTrue(
        shadowMedium.radius < shadowElevated.radius,
        "medium shadow radius < elevated shadow radius"
    )
    TestRunner.assertTrue(
        shadowSubtle.opacity < shadowMedium.opacity,
        "subtle shadow opacity < medium shadow opacity"
    )
    TestRunner.assertTrue(
        shadowMedium.opacity < shadowElevated.opacity,
        "medium shadow opacity < elevated shadow opacity"
    )
}

func testSpacingGrid() {
    TestRunner.setGroup("Spacing Grid (4pt base)")

    // All spacing values should be divisible by 2 (4pt grid alignment)
    TestRunner.assertTrue(
        DSTest.Spacing.xxs.truncatingRemainder(dividingBy: 2) == 0,
        "xxs is on 2pt grid"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.xs.truncatingRemainder(dividingBy: 4) == 0,
        "xs is on 4pt grid"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.sm.truncatingRemainder(dividingBy: 4) == 0,
        "sm is on 4pt grid"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.md.truncatingRemainder(dividingBy: 4) == 0,
        "md is on 4pt grid"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.lg.truncatingRemainder(dividingBy: 4) == 0,
        "lg is on 4pt grid"
    )
    TestRunner.assertTrue(
        DSTest.Spacing.xl.truncatingRemainder(dividingBy: 4) == 0,
        "xl is on 4pt grid"
    )
}

// MARK: - Main

@main
struct DesignSystemTests {
    static func main() {
        print("🎨 Design System Tests")
        print("==================================================")

        testRadiiOrdering()
        testRadiiValues()
        testSpacingOrdering()
        testSpacingValues()
        testShadowOrdering()
        testSpacingGrid()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
