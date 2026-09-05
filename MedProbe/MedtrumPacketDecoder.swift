//
//  MedtrumPacketDecoder.swift
//  MedProbe
//
//  Stateless decoder for Medtrum TouchCare Nano CGM notification packets.
//
//  Deliberately free of CoreBluetooth so it can be unit-tested without a radio.
//  This file understands exactly one thing: how to read glucose out of a 20-byte
//  notification. It knows nothing about pump commands and must never learn.
//

import Foundation

/// Why a packet was not accepted. Every rejection is logged with its reason.
enum MedtrumDecodeError: Error, Equatable {

    /// Packet was not the expected 20 bytes.
    case invalidLength(actual: Int)

    /// Byte 1 was not the CGM packet-type marker.
    case invalidPacketMarker(actual: UInt8)

    /// Calibration factor was zero — the value cannot be interpreted (and would divide by zero).
    case zeroCalibrationFactor

    /// Computed glucose fell outside the diagnostic plausibility window.
    case implausibleGlucose(mgdl: Double)

    /// Human-readable reason, used for the on-screen log and OSLog.
    var localizedDescription: String {
        switch self {
        case .invalidLength(let actual):
            return "unexpected packet length \(actual), expected \(MedtrumPacketDecoder.expectedPacketLength)"
        case .invalidPacketMarker(let actual):
            let known = MedtrumPacketDecoder.cgmPacketMarkers
                .sorted()
                .map { String(format: "0x%02X", $0) }
                .joined(separator: "/")
            return String(format: "packet marker 0x%02X at offset 1 is not one of %@", actual, known)
        case .zeroCalibrationFactor:
            return "calibration factor is 0"
        case .implausibleGlucose(let mgdl):
            return String(format: "implausible glucose %.1f mg/dL, outside %.0f-%.0f",
                          mgdl,
                          MedtrumPacketDecoder.minPlausibleMgdl,
                          MedtrumPacketDecoder.maxPlausibleMgdl)
        }
    }
}

/// Decodes Medtrum CGM notification packets.
///
/// Packet layout, taken from the xDrip4iOS reference implementation
/// (`CGMMedtrumTouchCareNanoTransmitter.swift`, JohanDegraeve/xdripswift). Only the fields
/// MedProbe actually needs are interpreted; unmapped bytes are left alone:
///
///     offset  0  packet type       (observed 0xB3 0x02)
///     offset  1  CGM type marker   (0x02) — the byte we fingerprint on
///     offset  4  uint16 LE  reading counter, +1 per 2-minute CGM cycle
///     offset  8  uint16 LE  current raw glucose
///     offset 10  uint16 LE  raw glucose 2 minutes ago
///     offset 12  uint16 LE  raw glucose 4 minutes ago
///     offset 14  uint16 LE  raw glucose 6 minutes ago
///     offset 18  uint16 LE  per-sensor calibration factor
///
/// Conversion: `mg/dL = rawGlucose * 1000 / calibrationFactor`.
enum MedtrumPacketDecoder {

    // MARK: - protocol constants

    /// CGM notifications are exactly this long.
    static let expectedPacketLength = 20

    /// Byte 1 distinguishes a CGM glucose packet from other traffic on the same characteristic.
    ///
    /// The xDrip4iOS reference documents 0x02, alongside 0xB3 at offset 0. This pump sends
    /// 0x06 with 0x6F at offset 0, and the rest of the layout is identical — verified on
    /// 2026-09-05 against EasyPatch, where four consecutive packets decoded to within
    /// 0.03 mmol/L of the values EasyPatch displayed.
    ///
    /// Kept as an explicit list rather than dropped altogether: accepting any byte here
    /// would leave unrelated 20-byte traffic to the plausibility gate alone.
    static let cgmPacketMarkers: Set<UInt8> = [0x02, 0x06]

    // MARK: - byte offsets

    private static let offsetPacketMarker = 1
    private static let offsetCounter = 4
    private static let offsetCurrentGlucose = 8
    private static let offsetHistory = [10, 12, 14]
    private static let offsetCalibrationFactor = 18

    // MARK: - plausibility window

    /// Lower bound of the diagnostic plausibility window, mg/dL.
    static let minPlausibleMgdl: Double = 40

    /// Upper bound of the diagnostic plausibility window, mg/dL.
    static let maxPlausibleMgdl: Double = 400

    // MARK: - decoding

    /// Validates and decodes one notification payload.
    ///
    /// - Parameters:
    ///   - data: the raw notification value, expected to be 20 bytes
    ///   - receivedAt: timestamp stamped onto the reading, injectable for tests
    /// - Returns: the decoded reading, or the reason it was rejected
    static func decode(_ data: Data, receivedAt: Date = Date()) -> Result<MedtrumReading, MedtrumDecodeError> {

        guard data.count == expectedPacketLength else {
            return .failure(.invalidLength(actual: data.count))
        }

        let marker = byte(data, at: offsetPacketMarker)
        guard cgmPacketMarkers.contains(marker) else {
            return .failure(.invalidPacketMarker(actual: marker))
        }

        let calibrationFactor = uint16LE(data, at: offsetCalibrationFactor)
        guard calibrationFactor > 0 else {
            return .failure(.zeroCalibrationFactor)
        }

        let rawGlucose = uint16LE(data, at: offsetCurrentGlucose)
        let mgdl = Double(rawGlucose) * 1000.0 / Double(calibrationFactor)

        // Defence in depth: a foreign 20-byte packet that happens to carry 0x02 at offset 1 is
        // very unlikely to also land inside a clinically meaningful range.
        guard mgdl >= minPlausibleMgdl, mgdl <= maxPlausibleMgdl else {
            return .failure(.implausibleGlucose(mgdl: mgdl))
        }

        let reading = MedtrumReading(
            receivedAt: receivedAt,
            counter: Int(uint16LE(data, at: offsetCounter)),
            rawGlucose: rawGlucose,
            calibrationFactor: calibrationFactor,
            mgdl: mgdl,
            historyRawGlucose: offsetHistory.map { uint16LE(data, at: $0) },
            rawPacketHex: hexString(data)
        )

        return .success(reading)
    }

    // MARK: - byte helpers

    /// Reads a byte at a logical offset. `Data` slices can start at a non-zero index,
    /// so every access is relative to `startIndex`.
    private static func byte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    /// Reads a little-endian uint16 at a logical offset.
    private static func uint16LE(_ data: Data, at offset: Int) -> UInt16 {
        let low = UInt16(byte(data, at: offset))
        let high = UInt16(byte(data, at: offset + 1))
        return (high << 8) | low
    }

    /// Uppercase, space-separated hex — the form used in the UI and the log.
    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
