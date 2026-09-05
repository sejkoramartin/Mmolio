//
//  StreamRecoveryTests.swift
//  MedProbeTests
//
//  Tests for the two pieces that recover a stalled CGM stream: the reconnect backoff
//  ladder and the stream tracker's watchdog, duplicate handling and backfill.
//
//  Both are pure value types, so the seven-minute watchdog is tested by passing times in
//  rather than by waiting seven minutes.
//

import XCTest
@testable import MedProbe

final class StreamRecoveryTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)

    /// Builds a decoded reading directly, bypassing the packet layout.
    private func reading(counter: Int,
                         raw: UInt16 = 307,
                         history: [UInt16] = [306, 305, 304],
                         calibration: UInt16 = 1037,
                         at offset: TimeInterval = 0) -> MedtrumReading {
        MedtrumReading(
            receivedAt: epoch.addingTimeInterval(offset),
            counter: counter,
            rawGlucose: raw,
            calibrationFactor: calibration,
            mgdl: Double(raw) * 1000.0 / Double(calibration),
            historyRawGlucose: history,
            rawPacketHex: "synthetic"
        )
    }

    // MARK: - reconnect backoff

    func testBackoffFollowsTheUpstreamLadderAndThenHolds() {
        var policy = ReconnectPolicy()

        XCTAssertEqual(policy.nextDelay(), 5)
        XCTAssertEqual(policy.nextDelay(), 10)
        XCTAssertEqual(policy.nextDelay(), 15)
        // Bounded, not exponential forever: it must not drift into hour-long waits.
        XCTAssertEqual(policy.nextDelay(), 15)
        XCTAssertEqual(policy.nextDelay(), 15)
        XCTAssertEqual(policy.attempt, 5)
    }

    func testResetReturnsToTheStartOfTheLadder() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()

        policy.reset()

        XCTAssertEqual(policy.attempt, 0)
        XCTAssertEqual(policy.nextDelay(), 5)
    }

    func testUpcomingDelayDoesNotAdvanceTheLadder() {
        var policy = ReconnectPolicy()

        XCTAssertEqual(policy.upcomingDelay, 5)
        XCTAssertEqual(policy.upcomingDelay, 5)
        XCTAssertEqual(policy.attempt, 0)

        _ = policy.nextDelay()
        XCTAssertEqual(policy.upcomingDelay, 10)
    }

    // MARK: - watchdog

    func testStreamIsNotStaleBetweenNormalCycles() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        // Three minutes on: one cycle missed, well inside the allowance.
        XCTAssertFalse(tracker.isStale(now: epoch.addingTimeInterval(180), since: epoch))
    }

    func testStreamIsStaleAfterTheInactivityTimeout() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        XCTAssertFalse(tracker.isStale(now: epoch.addingTimeInterval(6 * 60), since: epoch))
        XCTAssertTrue(tracker.isStale(now: epoch.addingTimeInterval(7 * 60), since: epoch))
    }

    func testASessionThatNeverDeliversIsAlsoCaught() {
        // The exact failure observed on the device: subscribed, isNotifying true, nothing
        // ever arrives. Measuring from the subscribe time is what makes this detectable.
        let tracker = CGMStreamTracker()

        XCTAssertNil(tracker.lastValidPacketAt)
        XCTAssertFalse(tracker.isStale(now: epoch.addingTimeInterval(5 * 60), since: epoch))
        XCTAssertTrue(tracker.isStale(now: epoch.addingTimeInterval(7 * 60), since: epoch))
    }

    func testAnyValidPacketRefreshesTheWatchdog() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        // Even a duplicate proves the link is alive.
        _ = tracker.accept(reading(counter: 100, at: 6 * 60))

        XCTAssertFalse(tracker.isStale(now: epoch.addingTimeInterval(12 * 60), since: epoch))
        XCTAssertTrue(tracker.isStale(now: epoch.addingTimeInterval(13 * 60), since: epoch))
    }

    // MARK: - duplicates

    func testRepeatedCounterIsReportedAsDuplicate() {
        var tracker = CGMStreamTracker()

        let first = tracker.accept(reading(counter: 5405))
        XCTAssertFalse(first.isDuplicate)

        let second = tracker.accept(reading(counter: 5405, at: 120))
        XCTAssertTrue(second.isDuplicate)
        XCTAssertTrue(second.backfilled.isEmpty)

        // A duplicate must not inflate the delivered count.
        XCTAssertEqual(tracker.deliveredCount, 1)
    }

    func testConsecutiveCountersProduceNoBackfill() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 5405))

        let update = tracker.accept(reading(counter: 5406, at: 120))

        XCTAssertEqual(update.missedCycles, 0)
        XCTAssertTrue(update.backfilled.isEmpty)
        XCTAssertEqual(tracker.deliveredCount, 2)
    }

    // MARK: - backfill

    func testSingleMissedCycleIsRecoveredFromTheFirstHistorySlot() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        // Counter jumps by two: exactly one cycle was missed.
        let update = tracker.accept(
            reading(counter: 102, raw: 310, history: [308, 306, 304], at: 240)
        )

        XCTAssertEqual(update.missedCycles, 1)
        XCTAssertEqual(update.backfilled.count, 1)

        let recovered = try? XCTUnwrap(update.backfilled.first)
        XCTAssertEqual(recovered?.counter, 101)
        XCTAssertEqual(recovered?.rawGlucose, 308)
        // One cycle before the live packet.
        XCTAssertEqual(recovered?.timestamp, epoch.addingTimeInterval(240 - 120))
        XCTAssertEqual(tracker.backfilledCount, 1)
        XCTAssertEqual(tracker.missedCycleCount, 0, "the gap was fully covered")
    }

    func testBackfillIsCappedAtThreeHistorySlots() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        // Ten cycles missed, but a packet only carries three previous readings.
        let update = tracker.accept(reading(counter: 110, at: 20 * 60))

        XCTAssertEqual(update.missedCycles, 9)
        XCTAssertEqual(update.backfilled.count, 3)
        XCTAssertEqual(tracker.backfilledCount, 3)
        // The six the packet could not carry are counted as genuinely lost.
        XCTAssertEqual(tracker.missedCycleCount, 6)
    }

    func testBackfilledReadingsAreOldestFirst() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        let update = tracker.accept(
            reading(counter: 104, raw: 310, history: [308, 306, 304], at: 8 * 60)
        )

        XCTAssertEqual(update.backfilled.map(\.counter), [101, 102, 103])
        XCTAssertEqual(update.backfilled.map(\.rawGlucose), [304, 306, 308])

        let timestamps = update.backfilled.map(\.timestamp)
        XCTAssertEqual(timestamps, timestamps.sorted(), "must be chronological")
    }

    func testImplausibleHistoryValuesAreNotBackfilled() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        // Middle slot decodes to far outside the plausibility window; the others are fine.
        let update = tracker.accept(
            reading(counter: 104, raw: 310, history: [308, 60000, 304], at: 8 * 60)
        )

        XCTAssertEqual(update.backfilled.count, 2)
        XCTAssertFalse(update.backfilled.contains { $0.rawGlucose == 60000 })
        // The rejected slot still counts as a cycle we never got.
        XCTAssertEqual(tracker.missedCycleCount, 1)
    }

    func testBackfillUsesTheSameConversionAsALiveReading() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        let update = tracker.accept(
            reading(counter: 102, raw: 307, history: [307, 306, 305], calibration: 1037, at: 240)
        )

        // 307 * 1000 / 1037, the value verified against EasyPatch.
        XCTAssertEqual(update.backfilled.first?.mgdl ?? 0, 296.05, accuracy: 0.01)
        XCTAssertEqual(update.backfilled.first?.mmoll ?? 0, 16.43, accuracy: 0.01)
    }

    // MARK: - sensor session changes

    func testCounterGoingBackwardsStartsAFreshSessionInsteadOfAHugeGap() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 5405))

        // New sensor: the counter restarts near zero.
        let update = tracker.accept(reading(counter: 3, at: 120))

        XCTAssertFalse(update.isDuplicate)
        XCTAssertEqual(update.missedCycles, 0)
        XCTAssertTrue(update.backfilled.isEmpty)
        XCTAssertEqual(tracker.lastDeliveredCounter, 3)
    }

    func testResettingStreamPositionTreatsTheNextReadingAsAFreshStart() {
        var tracker = CGMStreamTracker()
        _ = tracker.accept(reading(counter: 100))

        tracker.resetStreamPosition()
        let update = tracker.accept(reading(counter: 200, at: 120))

        XCTAssertEqual(update.missedCycles, 0)
        XCTAssertTrue(update.backfilled.isEmpty)
    }
}
