//
//  CGMSource.swift
//  MedProbe
//
//  What every glucose source must provide.
//
//  Sources differ enormously — one listens to a BLE characteristic, another polls an HTTP
//  service — so the protocol is deliberately small: publish readings, report state, and
//  say whether you are enabled. Everything source-specific stays behind the adapter.
//

import Foundation
import Combine

/// A source of glucose readings.
///
/// Implementations are expected to be main-queue confined, matching the rest of the app.
protocol CGMSource: AnyObject {

    /// Which source this is.
    var kind: GlucoseSourceKind { get }

    /// Most recent reading, or nil if none has arrived this session.
    var latestReading: GlucoseReading? { get }

    /// Emits every accepted reading. Duplicates and out-of-order readings are filtered by
    /// the source before publishing, so subscribers can trust what arrives here.
    var readingPublisher: AnyPublisher<GlucoseReading, Never> { get }

    /// Current connection state, for display.
    var state: GlucoseSourceState { get }

    /// Emits on every state change.
    var statePublisher: AnyPublisher<GlucoseSourceState, Never> { get }

    /// Begin producing readings. Idempotent.
    func start()

    /// Stop producing readings and release whatever the source holds. Idempotent.
    func stop()
}

/// Filters readings the way every source needs: no duplicates, nothing older than what we
/// already have.
///
/// Kept separate from the sources themselves so the rule is written once and tested once.
/// The comparison is per-source; sequences from different sources are never compared.
struct ReadingAcceptancePolicy {

    private(set) var lastAcceptedSequence: Int?
    private(set) var lastAcceptedMeasuredAt: Date?

    /// Why a reading was turned away.
    enum Rejection: Equatable {
        case duplicateSequence(Int)
        case olderSequence(incoming: Int, have: Int)
        case olderTimestamp(incoming: Date, have: Date)
    }

    /// Decides whether to accept a reading, updating state when it does.
    mutating func accept(_ reading: GlucoseReading) -> Result<GlucoseReading, Rejection> {

        if let last = lastAcceptedSequence {
            if reading.sequence == last {
                return .failure(.duplicateSequence(reading.sequence))
            }
            if reading.sequence < last {
                return .failure(.olderSequence(incoming: reading.sequence, have: last))
            }
        }

        // A sequence that moved forward while the timestamp moved backwards means the
        // source is confused; trust neither and refuse. This also guards a source whose
        // sequence is derived from the clock against a backwards clock adjustment.
        if let lastTime = lastAcceptedMeasuredAt, reading.measuredAt < lastTime {
            return .failure(.olderTimestamp(incoming: reading.measuredAt, have: lastTime))
        }

        lastAcceptedSequence = reading.sequence
        lastAcceptedMeasuredAt = reading.measuredAt
        return .success(reading)
    }

    /// Forgets position, for when a source restarts against a new sensor or account.
    mutating func reset() {
        lastAcceptedSequence = nil
        lastAcceptedMeasuredAt = nil
    }
}
