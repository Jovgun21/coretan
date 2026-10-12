import XCTest
@testable import Coretan

final class InkCodecTests: XCTestCase {

    private func sampleStroke() -> InkStroke {
        InkStroke(id: UUID(), tool: .pen,
                  color: InkColor(r: 0.12, g: 0.34, b: 0.56, a: 1.0),
                  baseWidth: 3.5, layerID: UUID(),
                  points: [
                    InkPoint(x: 10, y: 20, force: 0.4, altitude: 1.2, azimuth: 0.3, tOffset: 0),
                    InkPoint(x: 11.5, y: 21.25, force: 0.9, altitude: 1.4, azimuth: 0.35, tOffset: 17)
                  ], shape: nil)
    }

    func testRoundTripPreservesEverything() throws {
        let page = InkCodec.PagePayload(
            pageID: UUID(),
            size: .a4Portrait,
            template: .ruled,
            backgroundAsset: nil,
            layers: [InkLayer(id: UUID(), name: "Tinta", isVisible: true, isLocked: false, zIndex: 0)],
            strokes: [sampleStroke()],
            media: [])

        let encoded = InkCodec.encode(pages: [page])
        let decoded = try XCTUnwrap(InkCodec.decode(encoded))
        XCTAssertEqual(decoded.count, 1)

        let out = try XCTUnwrap(decoded.first)
        XCTAssertEqual(out.pageID, page.pageID)
        XCTAssertEqual(out.size, page.size)
        XCTAssertEqual(out.template, page.template)
        XCTAssertEqual(out.strokes.count, 1)

        let s = try XCTUnwrap(out.strokes.first)
        XCTAssertEqual(s, page.strokes[0], "Stroke must survive a save/open cycle unchanged")
    }

    func testRejectsCorruptHeader() {
        XCTAssertNil(InkCodec.decode(Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(InkCodec.decode(Data()))
    }

    func testEmptyPageListRoundTrips() throws {
        let encoded = InkCodec.encode(pages: [])
        let decoded = try XCTUnwrap(InkCodec.decode(encoded))
        XCTAssertTrue(decoded.isEmpty)
    }

    func testNullBackgroundAssetIsDistinctFromEmpty() throws {
        let page = InkCodec.PagePayload(pageID: UUID(), size: .letterPortrait, template: .blank,
                                        backgroundAsset: nil, layers: [], strokes: [], media: [])
        let out = try XCTUnwrap(InkCodec.decode(InkCodec.encode(pages: [page])).first)
        XCTAssertNil(out.backgroundAsset)
    }
}
