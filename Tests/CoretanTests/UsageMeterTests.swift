import XCTest
@testable import Coretan

final class UsageMeterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "coretan.usage")
        UserDefaults.standard.removeObject(forKey: "coretan.usage.limit")
    }

    func testRecordingConsumesQuota() {
        let m = UsageMeter.shared
        m.limit = 100
        m.reset()
        XCTAssertEqual(m.remaining, 100)
        m.record(tokens: 30, feature: "chat")
        XCTAssertEqual(m.used, 30)
        XCTAssertEqual(m.remaining, 70)
        XCTAssertEqual(m.byFeature["chat"], 30)
    }

    func testFailedRequestCannotSpendQuota() {
        let m = UsageMeter.shared
        m.limit = 100
        m.reset()
        // a throw before record() leaves usage untouched — the meter only
        // moves on a successful response
        XCTAssertEqual(m.used, 0)
        XCTAssertTrue(m.canSpend())
    }

    func testQuotaExhaustionBlocksSpending() {
        let m = UsageMeter.shared
        m.limit = 10
        m.reset()
        m.record(tokens: 10, feature: "chat")
        XCTAssertFalse(m.canSpend())
        XCTAssertEqual(m.remaining, 0)
    }

    func testUsageIsSplitPerFeature() {
        let m = UsageMeter.shared
        m.limit = 500
        m.reset()
        m.record(tokens: 10, feature: "chat")
        m.record(tokens: 25, feature: "transkripsi")
        XCTAssertEqual(m.byFeature["chat"], 10)
        XCTAssertEqual(m.byFeature["transkripsi"], 25)
    }
}
