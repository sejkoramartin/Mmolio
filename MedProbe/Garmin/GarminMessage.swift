//
//  GarminMessage.swift
//  MedProbe
//
//  The message MedProbe sends to the watch, and the rules for accepting one.
//
//  Connect IQ carries a dictionary between phone and device. The format is versioned from
//  the start because the watch app and the phone app are updated independently — a user
//  can easily be running last month's watch app against this week's phone build — and a
//  watch that cannot recognise a message must be able to say so rather than misread it.
//
//  Keys are single characters to keep the payload small; Connect IQ message size is
//  limited and the transfer costs battery on both ends.
//

import Foundation

/// A glucose reading encoded for the watch.
struct GarminMessage: Equatable {

    /// Bump when the meaning of any field changes. The watch refuses versions it does not
    /// know rather than guessing.
    static let currentVersion = 1

    let version: Int
    let mgdl: Double
    let trend: GlucoseTrend
    let measuredAt: Date
    let source: GlucoseSourceKind
    let sequence: Int

    init(reading: GlucoseReading, version: Int = GarminMessage.currentVersion) {
        self.version = version
        self.mgdl = reading.mgdl
        self.trend = reading.trend
        self.measuredAt = reading.measuredAt
        self.source = reading.source
        self.sequence = reading.sequence
    }

    init(version: Int, mgdl: Double, trend: GlucoseTrend, measuredAt: Date,
         source: GlucoseSourceKind, sequence: Int) {
        self.version = version
        self.mgdl = mgdl
        self.trend = trend
        self.measuredAt = measuredAt
        self.source = source
        self.sequence = sequence
    }

    // MARK: - wire format

    enum Key {
        static let version = "v"
        static let mgdl = "g"
        static let trend = "t"
        static let measuredAt = "m"
        static let source = "s"
        static let sequence = "q"
    }

    /// Encodes to the dictionary Connect IQ transports.
    ///
    /// Glucose is sent as an integer in mg/dL: Monkey C's float handling is awkward, the
    /// sensor resolution does not justify decimals, and the watch converts to mmol/L for
    /// display when the user asks for it. Time is a Unix timestamp in seconds.
    func encoded() -> [String: Any] {
        [
            Key.version: version,
            Key.mgdl: Int(mgdl.rounded()),
            Key.trend: trend.wireValue,
            Key.measuredAt: Int(measuredAt.timeIntervalSince1970),
            Key.source: source.wireValue,
            Key.sequence: sequence
        ]
    }

    /// Why a received dictionary could not be read.
    enum DecodeError: Error, Equatable {
        case missingField(String)
        case unsupportedVersion(Int)
    }

    /// Decodes a dictionary back into a message. Used by tests and by any future
    /// round-trip check; the watch has its own implementation in Monkey C.
    static func decode(_ payload: [String: Any]) -> Result<GarminMessage, DecodeError> {
        guard let version = payload[Key.version] as? Int else {
            return .failure(.missingField(Key.version))
        }
        guard version == currentVersion else {
            return .failure(.unsupportedVersion(version))
        }
        guard let mgdl = payload[Key.mgdl] as? Int else {
            return .failure(.missingField(Key.mgdl))
        }
        guard let trendValue = payload[Key.trend] as? Int else {
            return .failure(.missingField(Key.trend))
        }
        guard let measuredAt = payload[Key.measuredAt] as? Int else {
            return .failure(.missingField(Key.measuredAt))
        }
        guard let sourceValue = payload[Key.source] as? Int else {
            return .failure(.missingField(Key.source))
        }
        guard let sequence = payload[Key.sequence] as? Int else {
            return .failure(.missingField(Key.sequence))
        }

        let source = GlucoseSourceKind.allCases.first { $0.wireValue == sourceValue } ?? .medtrum

        return .success(
            GarminMessage(
                version: version,
                mgdl: Double(mgdl),
                trend: GlucoseTrend(wireValue: trendValue),
                measuredAt: Date(timeIntervalSince1970: TimeInterval(measuredAt)),
                source: source,
                sequence: sequence
            )
        )
    }
}

/// Decides which messages are worth sending, so the watch is not woken for a reading it
/// already has. The watch applies the same rule independently, because messages can
/// arrive out of order or be redelivered by the Connect IQ transport.
struct GarminSendPolicy {

    private(set) var lastSentSequence: Int?
    private(set) var lastSentSource: GlucoseSourceKind?
    private(set) var lastSentMeasuredAt: Date?

    enum Decision: Equatable {
        case send
        case skipDuplicate
        case skipOlder
    }

    /// A source change resets the comparison: sequences from different sources are not
    /// comparable, so switching source must not make the first new reading look stale.
    mutating func decide(_ reading: GlucoseReading) -> Decision {
        guard let lastSource = lastSentSource, lastSource == reading.source else {
            record(reading)
            return .send
        }

        if let lastSequence = lastSentSequence {
            if reading.sequence == lastSequence { return .skipDuplicate }
            if reading.sequence < lastSequence { return .skipOlder }
        }

        if let lastTime = lastSentMeasuredAt, reading.measuredAt < lastTime {
            return .skipOlder
        }

        record(reading)
        return .send
    }

    private mutating func record(_ reading: GlucoseReading) {
        lastSentSequence = reading.sequence
        lastSentSource = reading.source
        lastSentMeasuredAt = reading.measuredAt
    }

    mutating func reset() {
        lastSentSequence = nil
        lastSentSource = nil
        lastSentMeasuredAt = nil
    }
}
