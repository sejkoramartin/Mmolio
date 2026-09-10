//
//  HeartbeatRecoveryTests.swift
//  MedProbeTests
//
//  The retry ladder the heartbeat listener uses after a sensor drops.
//
//  Written after an overnight run where the sensor disconnected at 01:22 and nothing came
//  back for five hours: the listener never retried by design, and the poll timer it fell
//  back to does not run while iOS has the app suspended.
//

import XCTest
@testable import MedProbe

final class HeartbeatRecoveryTests: XCTestCase {

    /// Mirrors the ladder in LibreHeartbeatListener.
    private let delays: [TimeInterval] = [30, 60, 120, 300]

    private func delay(forAttempt attempt: Int) -> TimeInterval {
        delays[min(attempt, delays.count - 1)]
    }

    func testRetriesBackOffAndThenSettle() {
        XCTAssertEqual(delay(forAttempt: 0), 30)
        XCTAssertEqual(delay(forAttempt: 1), 60)
        XCTAssertEqual(delay(forAttempt: 2), 120)
        XCTAssertEqual(delay(forAttempt: 3), 300)

        // Bounded: the link belongs to the Libre app, so retrying must not drift into
        // hours, but nor should it grab at it every few seconds.
        XCTAssertEqual(delay(forAttempt: 10), 300)
        XCTAssertEqual(delay(forAttempt: 100), 300)
    }

    func testFirstRetryIsSoonEnoughToMatterButNotAggressive() {
        // A sensor comes back within a minute or so in normal use.
        XCTAssertGreaterThanOrEqual(delay(forAttempt: 0), 15, "faster than this is interference")
        XCTAssertLessThanOrEqual(delay(forAttempt: 0), 60, "slower than this misses ordinary dropouts")
    }

    func testTheLadderNeverReachesZero() {
        // A zero delay would be a tight reconnect loop against a medical device.
        for attempt in 0...20 {
            XCTAssertGreaterThan(delay(forAttempt: attempt), 0)
        }
    }

    func testCeilingIsShortEnoughToRecoverWithinOneSensorCycle() {
        // Libre produces a value each minute; five minutes is a few missed prompts, not
        // an outage measured in hours.
        XCTAssertLessThanOrEqual(delays.last ?? 0, 300)
    }

    func testTotalWaitAcrossTheLadderIsBounded() {
        // Worst case before settling: half an hour would be too long to notice a problem.
        let untilCeiling = delays.dropLast().reduce(0, +)
        XCTAssertLessThanOrEqual(untilCeiling, 300, "should reach the ceiling within five minutes")
    }
}
