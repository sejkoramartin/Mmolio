//
//  GlucoseNormalisationTests.swift
//  MedProbeTests
//
//  Unit conversion, trend derivation, and the acceptance rules every source shares.
//

import XCTest
@testable import MedProbe

final class GlucoseNormalisationTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)

    private func reading(mgdl: Double = 100,
                         at offset: TimeInterval = 0,
                         trend: GlucoseTrend = .steady,
                         source: GlucoseSourceKind = .medtrum,
                         sequence: Int = 1) -> GlucoseReading {
        GlucoseReading(mgdl: mgdl,
                       measuredAt: epoch.addingTimeInterval(offset),
                       trend: trend,
                       source: source,
                       sequence: sequence)
    }

    // MARK: - units

    func testMmolConversionMatchesTheVerifiedMedtrumValue() {
        // 307 raw / 1037 calibration = 296.05 mg/dL, which matched EasyPatch at 16.4.
        let value = reading(mgdl: 296.05)
        XCTAssertEqual(value.mmoll, 16.43, accuracy: 0.01)
    }

    func testConversionIsExactlyTheDocumentedDivisor() {
        XCTAssertEqual(reading(mgdl: 180.182).mmoll, 10.0, accuracy: 0.0001)
        XCTAssertEqual(GlucoseReading.mgdlPerMmoll, 18.0182)
    }

    // MARK: - age and staleness

    func testAgeIsMeasuredFromTheMeasurementTimeNotArrival() {
        let value = reading(at: -300)
        XCTAssertEqual(value.age(at: epoch), 300, accuracy: 0.001)
    }

    func testStalenessUsesTheGivenThreshold() {
        let value = reading(at: -600)

        XCTAssertFalse(value.isStale(at: epoch, threshold: 900))
        XCTAssertTrue(value.isStale(at: epoch, threshold: 600), "exactly at the threshold counts as stale")
        XCTAssertTrue(value.isStale(at: epoch, threshold: 300))
    }

    // MARK: - trend wire mapping

    func testEveryTrendSurvivesAWireRoundTrip() {
        for trend in GlucoseTrend.allCases {
            XCTAssertEqual(GlucoseTrend(wireValue: trend.wireValue), trend, "\(trend) did not round-trip")
        }
    }

    func testUnknownTrendIsDistinctFromSteady() {
        // A missing trend must never be rendered as a flat arrow.
        XCTAssertNotEqual(GlucoseTrend.unknown.wireValue, GlucoseTrend.steady.wireValue)
        XCTAssertEqual(GlucoseTrend(wireValue: 99), .unknown, "an unrecognised value falls back to unknown")
        XCTAssertEqual(GlucoseTrend.unknown.arrow, "?")
    }

    func testEverySourceSurvivesAWireRoundTrip() {
        for source in GlucoseSourceKind.allCases {
            let matched = GlucoseSourceKind.allCases.first { $0.wireValue == source.wireValue }
            XCTAssertEqual(matched, source)
        }
    }

    // MARK: - acceptance policy

    func testFirstReadingIsAlwaysAccepted() {
        var policy = ReadingAcceptancePolicy()
        XCTAssertNoThrow(try policy.accept(reading(sequence: 500)).get())
    }

    func testDuplicateSequenceIsRejected() {
        var policy = ReadingAcceptancePolicy()
        _ = policy.accept(reading(sequence: 10, at: 0))

        let result = policy.accept(reading(sequence: 10, at: 120))
        XCTAssertEqual(try? result.get(), nil)
        if case .failure(let rejection) = result {
            XCTAssertEqual(rejection, .duplicateSequence(10))
        } else {
            XCTFail("expected rejection")
        }
    }

    func testOlderSequenceIsRejected() {
        var policy = ReadingAcceptancePolicy()
        _ = policy.accept(reading(sequence: 10, at: 0))

        let result = policy.accept(reading(sequence: 9, at: 120))
        if case .failure(let rejection) = result {
            XCTAssertEqual(rejection, .olderSequence(incoming: 9, have: 10))
        } else {
            XCTFail("expected rejection")
        }
    }

    func testSequenceMovingForwardWhileTimeMovesBackwardsIsRejected() {
        // Guards a source whose sequence comes from the clock against a backwards jump.
        var policy = ReadingAcceptancePolicy()
        _ = policy.accept(reading(at: 0, sequence: 10))

        let result = policy.accept(reading(at: -600, sequence: 11))
        if case .failure(let rejection) = result {
            guard case .olderTimestamp = rejection else {
                return XCTFail("expected .olderTimestamp, got \(rejection)")
            }
        } else {
            XCTFail("expected rejection")
        }
    }

    func testNewerReadingIsAccepted() {
        var policy = ReadingAcceptancePolicy()
        _ = policy.accept(reading(sequence: 10, at: 0))

        XCTAssertNoThrow(try policy.accept(reading(sequence: 11, at: 120)).get())
        XCTAssertEqual(policy.lastAcceptedSequence, 11)
    }

    func testResetForgetsPosition() {
        var policy = ReadingAcceptancePolicy()
        _ = policy.accept(reading(sequence: 5000, at: 0))

        policy.reset()

        // A new sensor restarts the counter; without reset this would look ancient.
        XCTAssertNoThrow(try policy.accept(reading(sequence: 3, at: 120)).get())
    }

    // MARK: - Medtrum adapter

    private func medtrumReading(counter: Int = 100,
                                raw: UInt16 = 307,
                                history: [UInt16] = [307, 306, 305],
                                calibration: UInt16 = 1037) -> MedtrumReading {
        MedtrumReading(receivedAt: epoch,
                       counter: counter,
                       rawGlucose: raw,
                       calibrationFactor: calibration,
                       mgdl: Double(raw) * 1000.0 / Double(calibration),
                       historyRawGlucose: history,
                       rawPacketHex: "synthetic")
    }

    func testMedtrumAdapterPreservesTheDecodedValue() {
        let normalised = MedtrumReadingAdapter.normalise(medtrumReading())

        // The verified value must survive normalisation untouched.
        XCTAssertEqual(normalised.mgdl, 296.05, accuracy: 0.01)
        XCTAssertEqual(normalised.mmoll, 16.43, accuracy: 0.01)
        XCTAssertEqual(normalised.source, .medtrum)
        XCTAssertEqual(normalised.sequence, 100, "the reading counter is the sequence")
        XCTAssertEqual(normalised.measuredAt, epoch)
    }

    func testMedtrumTrendComesFromTheHistorySlots() {
        // 307 now against 307 one cycle ago: flat.
        XCTAssertEqual(MedtrumReadingAdapter.trend(from: medtrumReading(raw: 307, history: [307, 306, 305])), .steady)

        // Rising: 340 against 307 is +9.5 mg/dL per cycle.
        XCTAssertEqual(MedtrumReadingAdapter.trend(from: medtrumReading(raw: 340, history: [307, 306, 305])), .risingQuickly)

        // Falling gently: 300 against 307 is about -6.8 mg/dL per cycle.
        XCTAssertEqual(MedtrumReadingAdapter.trend(from: medtrumReading(raw: 300, history: [307, 306, 305])), .fallingQuickly)
    }

    func testMedtrumTrendIsUnknownWithoutUsableHistory() {
        XCTAssertEqual(MedtrumReadingAdapter.trend(from: medtrumReading(history: [])), .unknown)
        XCTAssertEqual(MedtrumReadingAdapter.trend(from: medtrumReading(calibration: 0)), .unknown)
    }

    func testBackfilledReadingKeepsItsOwnTimestampAndClaimsNoTrend() {
        let backfilled = BackfilledReading(counter: 99,
                                           rawGlucose: 300,
                                           mgdl: 289.3,
                                           timestamp: epoch.addingTimeInterval(-120))

        let normalised = MedtrumReadingAdapter.normalise(backfilled)

        XCTAssertEqual(normalised.sequence, 99)
        XCTAssertEqual(normalised.measuredAt, epoch.addingTimeInterval(-120),
                       "a backfilled value belongs to its own cycle, not to the carrying packet")
        XCTAssertEqual(normalised.trend, .unknown,
                       "one historical value says nothing about direction")
    }
}
