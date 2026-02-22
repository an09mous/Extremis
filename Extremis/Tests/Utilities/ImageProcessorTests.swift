// MARK: - Image Processor Tests
// Tests for image processing utility (resize calculations, encoding logic)

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

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got value"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
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

// MARK: - Extracted Logic Under Test
// We test the pure logic from ImageProcessor without requiring AppKit/NSImage

typealias CGFloat = Double

/// Extracted target size calculation (same logic as ImageProcessor.calculateTargetSize)
func calculateTargetSize(width: CGFloat, height: CGFloat, maxEdge: CGFloat) -> (CGFloat, CGFloat) {
    // If both dimensions are within limits, no resize needed
    if width <= maxEdge && height <= maxEdge {
        return (width, height)
    }

    // Scale based on the larger dimension
    let scale: CGFloat
    if width >= height {
        scale = maxEdge / width
    } else {
        scale = maxEdge / height
    }

    return (round(width * scale), round(height * scale))
}

/// Determine whether to use PNG or JPEG based on alpha presence
func shouldUsePNG(hasAlpha: Bool) -> Bool {
    return hasAlpha
}

// MARK: - Tests

func testCalculateTargetSizeNoResize() {
    TestRunner.setGroup("calculateTargetSize - No Resize Needed")

    let maxEdge: CGFloat = 1568.0

    // Small image - no resize
    let (w1, h1) = calculateTargetSize(width: 800, height: 600, maxEdge: maxEdge)
    TestRunner.assertEqual(w1, 800, "Small image width unchanged")
    TestRunner.assertEqual(h1, 600, "Small image height unchanged")

    // Exactly at max - no resize
    let (w2, h2) = calculateTargetSize(width: 1568, height: 1568, maxEdge: maxEdge)
    TestRunner.assertEqual(w2, 1568, "Max-edge image width unchanged")
    TestRunner.assertEqual(h2, 1568, "Max-edge image height unchanged")

    // One dimension at max, other smaller - no resize
    let (w3, h3) = calculateTargetSize(width: 1568, height: 1000, maxEdge: maxEdge)
    TestRunner.assertEqual(w3, 1568, "Width at max, height smaller - width unchanged")
    TestRunner.assertEqual(h3, 1000, "Width at max, height smaller - height unchanged")

    // Tiny image
    let (w4, h4) = calculateTargetSize(width: 100, height: 50, maxEdge: maxEdge)
    TestRunner.assertEqual(w4, 100, "Tiny image width unchanged")
    TestRunner.assertEqual(h4, 50, "Tiny image height unchanged")
}

func testCalculateTargetSizeWideImage() {
    TestRunner.setGroup("calculateTargetSize - Wide Image")

    let maxEdge: CGFloat = 1568.0

    // 4000x2000 - scale by width
    let (w1, h1) = calculateTargetSize(width: 4000, height: 2000, maxEdge: maxEdge)
    TestRunner.assertEqual(w1, 1568, "Wide image width scaled to max")
    TestRunner.assertEqual(h1, 784, "Wide image height scaled proportionally") // 2000 * (1568/4000) = 784

    // 3000x1000 - wider ratio
    let (w2, h2) = calculateTargetSize(width: 3000, height: 1000, maxEdge: maxEdge)
    TestRunner.assertEqual(w2, 1568, "Very wide image width scaled to max")
    // 1000 * (1568/3000) = 522.67 -> 523
    TestRunner.assertEqual(h2, 523, "Very wide image height scaled proportionally")
}

func testCalculateTargetSizeTallImage() {
    TestRunner.setGroup("calculateTargetSize - Tall Image")

    let maxEdge: CGFloat = 1568.0

    // 1000x3000 - scale by height
    let (w1, h1) = calculateTargetSize(width: 1000, height: 3000, maxEdge: maxEdge)
    // 1000 * (1568/3000) = 522.67 -> 523
    TestRunner.assertEqual(w1, 523, "Tall image width scaled proportionally")
    TestRunner.assertEqual(h1, 1568, "Tall image height scaled to max")

    // 500x5000 - very tall
    let (w2, h2) = calculateTargetSize(width: 500, height: 5000, maxEdge: maxEdge)
    // 500 * (1568/5000) = 156.8 -> 157
    TestRunner.assertEqual(w2, 157, "Very tall image width scaled proportionally")
    TestRunner.assertEqual(h2, 1568, "Very tall image height scaled to max")
}

func testCalculateTargetSizeSquareImage() {
    TestRunner.setGroup("calculateTargetSize - Square Image")

    let maxEdge: CGFloat = 1568.0

    // 2000x2000 square - scale by either dimension
    let (w1, h1) = calculateTargetSize(width: 2000, height: 2000, maxEdge: maxEdge)
    TestRunner.assertEqual(w1, 1568, "Square image width scaled to max")
    TestRunner.assertEqual(h1, 1568, "Square image height scaled to max")

    // 1568x1568 - exactly at max
    let (w2, h2) = calculateTargetSize(width: 1568, height: 1568, maxEdge: maxEdge)
    TestRunner.assertEqual(w2, 1568, "At-max square width unchanged")
    TestRunner.assertEqual(h2, 1568, "At-max square height unchanged")
}

func testCalculateTargetSizeCustomMaxEdge() {
    TestRunner.setGroup("calculateTargetSize - Custom Max Edge")

    // Smaller max edge (e.g., thumbnail)
    let (w1, h1) = calculateTargetSize(width: 1000, height: 500, maxEdge: 200)
    TestRunner.assertEqual(w1, 200, "Custom max: width scaled to 200")
    TestRunner.assertEqual(h1, 100, "Custom max: height scaled proportionally")

    // Larger max edge
    let (w2, h2) = calculateTargetSize(width: 5000, height: 3000, maxEdge: 4000)
    TestRunner.assertEqual(w2, 4000, "Large max: width scaled to 4000")
    TestRunner.assertEqual(h2, 2400, "Large max: height scaled proportionally")
}

func testEncodingSelection() {
    TestRunner.setGroup("Encoding Selection (PNG vs JPEG)")

    // Images with alpha should use PNG
    TestRunner.assertTrue(shouldUsePNG(hasAlpha: true), "Alpha image should use PNG")

    // Images without alpha should use JPEG
    TestRunner.assertFalse(shouldUsePNG(hasAlpha: false), "Non-alpha image should use JPEG")
}

func testAspectRatioPreservation() {
    TestRunner.setGroup("Aspect Ratio Preservation")

    let maxEdge: CGFloat = 1568.0

    // Test that aspect ratio is preserved within tolerance
    let testCases: [(CGFloat, CGFloat)] = [
        (4000, 3000),  // 4:3
        (1920, 1080),  // 16:9
        (3000, 3000),  // 1:1
        (800, 2400),   // 1:3
        (7680, 4320),  // 16:9 (8K)
    ]

    for (origW, origH) in testCases {
        let origRatio = origW / origH
        let (newW, newH) = calculateTargetSize(width: origW, height: origH, maxEdge: maxEdge)
        let newRatio = newW / newH
        let ratioDiff = abs(origRatio - newRatio)
        // Allow small rounding error (< 1%)
        let tolerance = origRatio * 0.01
        TestRunner.assertTrue(ratioDiff <= tolerance,
            "Aspect ratio preserved for \(Int(origW))x\(Int(origH)): original=\(String(format: "%.3f", origRatio)), new=\(String(format: "%.3f", newRatio))")
    }
}

// MARK: - Main Entry Point

@main
struct ImageProcessorTests {
    static func main() {
        print("")
        print("==================================================")
        print("IMAGE PROCESSOR TESTS")
        print("==================================================")

        testCalculateTargetSizeNoResize()
        testCalculateTargetSizeWideImage()
        testCalculateTargetSizeTallImage()
        testCalculateTargetSizeSquareImage()
        testCalculateTargetSizeCustomMaxEdge()
        testEncodingSelection()
        testAspectRatioPreservation()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
