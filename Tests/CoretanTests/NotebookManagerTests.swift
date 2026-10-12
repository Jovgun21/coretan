import XCTest
@testable import Coretan

final class NotebookManagerTests: XCTestCase {

    private var notebookID = UUID()

    override func setUp() {
        super.setUp()
        notebookID = UUID()
    }

    func testPageInsertKeepsSequentialIndices() {
        let mgr = NotebookManager()
        let p0 = PageMeta(id: UUID(), notebookID: notebookID, index: 0, size: .a4Portrait,
                          template: .ruled, thumbnailName: nil)
        mgr.savePages([p0], for: notebookID)
        let p1 = mgr.addPage(after: 0, notebookID: notebookID, template: .grid, size: .a4Portrait)
        let pages = mgr.loadPages(for: notebookID)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map(\.index), [0, 1], "Indices must stay dense and ordered")
        XCTAssertEqual(pages[1].id, p1.id)
    }

    func testDeletingEveryPageStillLeavesOne() {
        let mgr = NotebookManager()
        let p0 = PageMeta(id: UUID(), notebookID: notebookID, index: 0, size: .a4Portrait,
                          template: .ruled, thumbnailName: nil)
        mgr.savePages([p0], for: notebookID)
        mgr.deletePages(ids: [p0.id], notebookID: notebookID)
        XCTAssertEqual(mgr.loadPages(for: notebookID).count, 1,
                       "A notebook must never end up with zero pages")
    }

    func testDeletedPageGoesToTrashAndCanReturn() {
        let mgr = NotebookManager()
        let a = PageMeta(id: UUID(), notebookID: notebookID, index: 0, size: .a4Portrait, template: .ruled, thumbnailName: nil)
        let b = PageMeta(id: UUID(), notebookID: notebookID, index: 1, size: .a4Portrait, template: .dotGrid, thumbnailName: nil)
        mgr.savePages([a, b], for: notebookID)

        mgr.deletePages(ids: [b.id], notebookID: notebookID)
        XCTAssertEqual(mgr.loadPages(for: notebookID).count, 1)
        XCTAssertEqual(mgr.trash.count, 1)

        mgr.restoreFromTrash([b.id], notebookID: notebookID)
        XCTAssertEqual(mgr.loadPages(for: notebookID).count, 2, "Soft delete must be reversible")
        XCTAssertTrue(mgr.trash.isEmpty)
    }

    func testReorderMovesPageWithoutLosingIt() {
        let mgr = NotebookManager()
        let ids = (0..<3).map { _ in UUID() }
        let pages = ids.enumerated().map { i, id in
            PageMeta(id: id, notebookID: notebookID, index: i, size: .a4Portrait, template: .ruled, thumbnailName: nil)
        }
        mgr.savePages(pages, for: notebookID)
        mgr.movePage(from: 0, to: 2, notebookID: notebookID)
        let out = mgr.loadPages(for: notebookID)
        XCTAssertEqual(out.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(out.map(\.index), [0, 1, 2])
    }

    func testRotateSwapsPageSize() {
        let mgr = NotebookManager()
        let p = PageMeta(id: UUID(), notebookID: notebookID, index: 0, size: .a4Portrait, template: .ruled, thumbnailName: nil)
        mgr.savePages([p], for: notebookID)
        mgr.rotate(pageID: p.id, notebookID: notebookID)
        let out = mgr.loadPages(for: notebookID)[0]
        XCTAssertEqual(out.size.width, PageSize.a4Portrait.height)
        XCTAssertEqual(out.size.height, PageSize.a4Portrait.width)
    }

    func testStrokeSaveLoadRoundTrip() {
        let mgr = NotebookManager()
        let s = InkStroke(id: UUID(), tool: .highlighter,
                          color: InkColor(r: 1, g: 1, b: 0, a: 1), baseWidth: 12,
                          layerID: UUID(),
                          points: [InkPoint(x: 5, y: 5, force: 1, altitude: 1.5, azimuth: 0, tOffset: 0),
                                   InkPoint(x: 90, y: 5, force: 1, altitude: 1.5, azimuth: 0, tOffset: 40)],
                          shape: nil)
        mgr.saveStrokes([s], pageID: p0ID, notebookID: notebookID, size: .a4Portrait, template: .ruled)
        let back = mgr.loadStrokes(pageID: p0ID, notebookID: notebookID)
        XCTAssertEqual(back, [s])
    }

    private var p0ID = UUID()
}
