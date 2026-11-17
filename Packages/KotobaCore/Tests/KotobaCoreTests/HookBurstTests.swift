import XCTest
@testable import KotobaCore

final class HookBurstTests: XCTestCase {
    func testOneLiveLineGoesOutAfterTheQuietGap() {
        var burst = HookBurst<String>(quiet: 0.06, maxWait: 0.2)
        XCTAssertNil(burst.deadline)
        XCTAssertEqual(burst.add("一", at: 10), 10.06, accuracy: 1e-9)
        XCTAssertNil(burst.take(at: 10.03))
        XCTAssertEqual(burst.take(at: 10.06), ["一"])
        XCTAssertNil(burst.deadline)
        XCTAssertNil(burst.take(at: 11))
    }

    /// The catch-up after the phone slept: many lines a few ms apart are one batch,
    /// newest last, so the screen can jump straight to it.
    func testBacklogArrivesAsOneBatch() {
        var burst = HookBurst<Int>(quiet: 0.06, maxWait: 0.2)
        for i in 0..<30 { burst.add(i, at: 5 + Double(i) * 0.004) }
        XCTAssertNil(burst.take(at: 5 + 29 * 0.004 + 0.03))
        let batch = burst.take(at: 5 + 29 * 0.004 + 0.06)
        XCTAssertEqual(batch, Array(0..<30))
    }

    /// A stream that never pauses still reaches the screen every maxWait.
    func testSteadyStreamIsNotHeldForever() {
        var burst = HookBurst<Int>(quiet: 0.06, maxWait: 0.2)
        var batches: [[Int]] = []
        for i in 0..<100 {
            let now = Double(i) * 0.01
            if let batch = burst.take(at: now) { batches.append(batch) }
            burst.add(i, at: now)
        }
        XCTAssertGreaterThanOrEqual(batches.count, 4)
        XCTAssertTrue(batches.allSatisfy { $0.count <= 21 })
        XCTAssertEqual(batches.flatMap { $0 } + burst.takeAll(), Array(0..<100))
    }

    func testTakeAllEmpties() {
        var burst = HookBurst<String>()
        burst.add("a", at: 0)
        burst.add("b", at: 0.01)
        XCTAssertEqual(burst.takeAll(), ["a", "b"])
        XCTAssertTrue(burst.pending.isEmpty)
        XCTAssertEqual(burst.takeAll(), [])
    }
}
