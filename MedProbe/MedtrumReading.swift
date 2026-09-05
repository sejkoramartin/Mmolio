//
//  MedtrumReading.swift
//  MedProbe
//
//  Result of decoding one Medtrum CGM notification packet.
//  Pure value type — no CoreBluetooth, no Foundation beyond Date/Data, fully unit-testable.
//

import Foundation

/// One successfully decoded CGM notification from the Medtrum patch pump.
///
/// Everything in here is *observed* data: the raw counter and glucose values as they arrived,
/// plus the derived clinical units. Nothing here relates to therapy control — MedProbe only
/// ever listens.
struct MedtrumReading: Equatable {

    /// mg/dL per mmol/L, the standard molar mass conversion for glucose.
    static let mgdlPerMmoll: Double = 18.0182

    /// Wall-clock time the packet was handed to the decoder.
    let receivedAt: Date

    /// Reading counter, uint16 LE at offset 4. Ticks once per 2-minute CGM cycle since sensor start.
    let counter: Int

    /// Current raw glucose, uint16 LE at offset 8. Uncalibrated sensor units.
    let rawGlucose: UInt16

    /// Per-sensor calibration factor, uint16 LE at offset 18.
    let calibrationFactor: UInt16

    /// Current glucose in mg/dL: `rawGlucose * 1000 / calibrationFactor`.
    let mgdl: Double

    /// Raw glucose values for the three previous 2-minute cycles (offsets 10, 12, 14).
    /// Diagnostic only — MedProbe does not build a history database from these.
    let historyRawGlucose: [UInt16]

    /// The complete 20-byte packet, uppercase hex, space separated.
    let rawPacketHex: String

    /// Current glucose in mmol/L.
    var mmoll: Double {
        mgdl / Self.mgdlPerMmoll
    }

    /// How long the sensor has been running, inferred from the counter, which ticks once
    /// per 2-minute CGM cycle since sensor start.
    var sensorAge: TimeInterval {
        TimeInterval(counter * 2 * 60)
    }

    /// The three previous cycles converted with the same calibration factor.
    /// Not plausibility-filtered — these are shown for diagnostics, never used as a reading.
    var historyMgdl: [Double] {
        guard calibrationFactor > 0 else { return [] }
        return historyRawGlucose.map { Double($0) * 1000.0 / Double(calibrationFactor) }
    }
}
