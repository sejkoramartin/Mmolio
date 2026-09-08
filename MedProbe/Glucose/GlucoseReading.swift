//
//  GlucoseReading.swift
//  MedProbe
//
//  One glucose measurement, normalised across sources.
//
//  Medtrum and LibreLinkUp report different units, different trend vocabularies and
//  different identifiers. Everything downstream — deduplication, staleness, the Garmin
//  message — works on this type alone, so adding a third source later means writing an
//  adapter rather than touching the transport.
//
//  Pure value type: no networking, no CoreBluetooth, no clock of its own.
//

import Foundation

/// Where a reading came from. Encoded into the Garmin message, so the watch can show it.
enum GlucoseSourceKind: String, Codable, CaseIterable {
    case medtrum
    case libreLinkUp

    var displayName: String {
        switch self {
        case .medtrum: return "Medtrum"
        case .libreLinkUp: return "LibreLinkUp"
        }
    }

    /// Compact form for the wire protocol.
    var wireValue: Int {
        switch self {
        case .medtrum: return 1
        case .libreLinkUp: return 2
        }
    }
}

/// Direction of change. Deliberately a small closed set: every source maps into it, and
/// the watch renders exactly these seven states.
enum GlucoseTrend: String, Codable, CaseIterable {
    case fallingQuickly
    case falling
    case fallingSlightly
    case steady
    case risingSlightly
    case rising
    case risingQuickly

    /// Unknown trend is represented by absence, not by a case, so a missing trend cannot
    /// be mistaken for "steady".
    case unknown

    var arrow: String {
        switch self {
        case .fallingQuickly: return "↓↓"
        case .falling: return "↓"
        case .fallingSlightly: return "↘"
        case .steady: return "→"
        case .risingSlightly: return "↗"
        case .rising: return "↑"
        case .risingQuickly: return "↑↑"
        case .unknown: return "?"
        }
    }

    /// Compact form for the wire protocol, ordered so the watch can render from an index.
    var wireValue: Int {
        switch self {
        case .fallingQuickly: return 1
        case .falling: return 2
        case .fallingSlightly: return 3
        case .steady: return 4
        case .risingSlightly: return 5
        case .rising: return 6
        case .risingQuickly: return 7
        case .unknown: return 0
        }
    }

    init(wireValue: Int) {
        self = GlucoseTrend.allCases.first { $0.wireValue == wireValue } ?? .unknown
    }
}

/// A normalised glucose measurement.
struct GlucoseReading: Equatable, Codable {

    /// mg/dL per mmol/L. The canonical unit here is mg/dL because both sources' native
    /// arithmetic is integral in it; mmol/L is derived for display.
    static let mgdlPerMmoll: Double = 18.0182

    /// Canonical value, mg/dL.
    let mgdl: Double

    /// When the measurement was taken — not when it reached us. A reading recovered from
    /// a backfill slot carries the time of the cycle it belongs to.
    let measuredAt: Date

    let trend: GlucoseTrend

    let source: GlucoseSourceKind

    /// Monotonically increasing per source, used for deduplication and ordering.
    ///
    /// Medtrum has a natural one: the reading counter. LibreLinkUp has none, so its
    /// adapter derives a sequence from the measurement timestamp. The only contract is
    /// that a larger number means a later reading *from the same source*; values are
    /// never compared across sources.
    let sequence: Int

    var mmoll: Double {
        mgdl / Self.mgdlPerMmoll
    }

    /// How old the reading is at a given moment.
    func age(at now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(measuredAt)
    }

    /// True when the reading is too old to be presented as current.
    func isStale(at now: Date = Date(), threshold: TimeInterval) -> Bool {
        age(at: now) >= threshold
    }
}

/// Why a source currently has nothing to offer. Surfaced in the UI so a silent source is
/// never indistinguishable from a working one.
enum GlucoseSourceError: Error, Equatable {

    /// The source is switched off in settings.
    case disabled

    /// Credentials are missing or were rejected.
    case notAuthenticated(String)

    /// Reached the service or the device, but it had nothing to give.
    case noReadingAvailable

    /// Network or transport failure.
    case transport(String)

    /// The service answered with something we could not interpret.
    case decoding(String)

    /// Refused to act because a rate limit would be exceeded.
    case rateLimited(retryAfter: TimeInterval)

    var userFacingDescription: String {
        switch self {
        case .disabled:
            return "Source is switched off"
        case .notAuthenticated(let detail):
            return "Not signed in: \(detail)"
        case .noReadingAvailable:
            return "No reading available yet"
        case .transport(let detail):
            return "Connection problem: \(detail)"
        case .decoding(let detail):
            return "Unexpected response: \(detail)"
        case .rateLimited(let retryAfter):
            return "Waiting \(Int(retryAfter))s before asking again"
        }
    }
}

/// Connection state of a source, for display.
enum GlucoseSourceState: Equatable {
    case disabled
    case idle
    case connecting
    case connected
    case failed(GlucoseSourceError)

    var isUsable: Bool {
        self == .connected
    }
}
