import XCTest
@testable import Coretan

final class ShapeRecognizerTests: XCTestCase {

    private func stroke(_ pts: [(Float, Float)]) -> [InkPoint] {
        pts.enumerated().map { i, p in
            InkPoint(x: p.0, y: p.1, force: 0.8, altitude: 1.5, azimuth: 0, tOffset: Int32(i * 10))
        }
    }

    func testRecognizesStraightLine() throws {
        let pts = stride(from: 0, through: 100, by: 5).map { (Float($0), Float(50)) }
        let r = try XCTUnwrap(ShapeRecognizer.recognize(points: stroke(pts)))
        XCTAssertEqual(r.kind, .line)
        XCTAssertGreaterThan(r.confidence, 0.9)
    }

    func testRecognizesRectangle() throws {
        var pts: [(Float, Float)] = []
        pts += stride(from: 0, through: 100, by: 5).map { (Float($0), 0) }
        pts += stride(from: 5, through: 100, by: 5).map { (100, Float($0)) }
        pts += stride(from: 95, through: 0, by: -5).map { (Float($0), 100) }
        pts += stride(from: 95, through: 0, by: -5).map { (0, Float($0)) }
        let r = try XCTUnwrap(ShapeRecognizer.recognize(points: stroke(pts)))
        XCTAssertTrue([.rect, .diamond].contains(r.kind), "Got \(r.kind)")
    }

    func testRecognizesCircle() throws {
        var pts: [(Float, Float)] = []
        for i in 0..<72 {
            let a = Double(i) / 72.0 * 2 * .pi
            pts.append((Float(50 + 40 * cos(a)), Float(50 + 40 * sin(a))))
        }
        pts.append(pts[0])
        let r = try XCTUnwrap(ShapeRecognizer.recognize(points: stroke(pts)))
        XCTAssertEqual(r.kind, .ellipse)
    }

    func testTooShortStrokeIsRejected() {
        XCTAssertNil(ShapeRecognizer.recognize(points: stroke([(0, 0), (1, 1)])))
    }

    func testArrowPromotionWhenEndHooks() {
        var pts: [(Float, Float)] = stride(from: 0, through: 80, by: 8).map { (Float($0), 0) }
        pts.append((72, 12))
        let base = ShapeRecognizer.Result(kind: .line, a: .zero, b: .zero, confidence: 0.9)
        let promoted = ShapeRecognizer.arrowIfPossible(base, points: stroke(pts))
        XCTAssertEqual(promoted.kind, .arrow)
    }
}
