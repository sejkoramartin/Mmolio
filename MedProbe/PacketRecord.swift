//
//  PacketRecord.swift
//  MedProbe
//
//  One recorded line of the capture: either a notification we received, or a
//  glucose reading the user read off EasyPatch and marked by hand.
//
//  Pure value type with its own serialisation — no CoreBluetooth, no file system —
//  so the CSV format is unit-testable.
//
//  This file records observations. It assigns no meaning to any byte.
//

import Foundation

/// What a recorded row represents.
enum PacketRecordKind: String, Codable {

    /// A BLE notification received from the pump.
    case packet

    /// A glucose value the user read from EasyPatch and marked manually.
    /// Stored alongside the packets purely so the two can be correlated offline.
    /// It is never fed back into decoding.
    case groundTruth
}

/// One row of the capture file.
struct PacketRecord: Codable, Equatable, Identifiable {

    var id: String { "\(timestamp.timeIntervalSince1970)-\(characteristic)-\(hex)" }

    let kind: PacketRecordKind
    let timestamp: Date

    /// Characteristic UUID for a packet; a fixed marker label for a ground-truth row.
    let characteristic: String

    let length: Int
    let hex: String

    /// Marker used in the `characteristic` column for manually entered EasyPatch readings,
    /// so a single flat file still carries both streams without a schema change.
    static let groundTruthMarker = "EASYPATCH_MMOL_L"

    // MARK: - construction

    static func packet(timestamp: Date, characteristic: String, data: Data) -> PacketRecord {
        PacketRecord(
            kind: .packet,
            timestamp: timestamp,
            characteristic: characteristic,
            length: data.count,
            hex: MedtrumPacketDecoder.hexString(data)
        )
    }

    static func groundTruth(timestamp: Date, mmoll: Double) -> PacketRecord {
        PacketRecord(
            kind: .groundTruth,
            timestamp: timestamp,
            characteristic: groundTruthMarker,
            length: 0,
            hex: String(format: "%.1f", mmoll)
        )
    }

    // MARK: - framing observations
    //
    // Byte 2 and byte 3 are recorded and displayed because their behaviour is visible
    // without interpretation: across captured frames byte 2 changes per message while
    // byte 3 runs 01, 02, … within a message. What they *mean* is unknown, so they are
    // named after their position, not after a guess.

    /// Byte at offset 2, when the frame is long enough to have one.
    var byteAtOffset2: UInt8? {
        Self.byte(fromHex: hex, at: 2)
    }

    /// Byte at offset 3, when the frame is long enough to have one.
    var byteAtOffset3: UInt8? {
        Self.byte(fromHex: hex, at: 3)
    }

    /// Compact label for the live view, e.g. "3D/01". Nil for ground-truth rows.
    var framingLabel: String? {
        guard kind == .packet,
              let b2 = byteAtOffset2,
              let b3 = byteAtOffset3 else { return nil }
        return String(format: "%02X/%02X", b2, b3)
    }

    private static func byte(fromHex hex: String, at index: Int) -> UInt8? {
        let parts = hex.split(separator: " ")
        guard index < parts.count else { return nil }
        return UInt8(parts[index], radix: 16)
    }

    // MARK: - CSV

    /// Column header, exactly the four columns requested for offline analysis.
    static let csvHeader = "timestamp,characteristic,length,hex"

    /// ISO 8601 with milliseconds, so packets arriving within the same second stay ordered.
    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var csvRow: String {
        [
            Self.timestampFormatter.string(from: timestamp),
            Self.escapeCSV(characteristic),
            String(length),
            Self.escapeCSV(hex)
        ].joined(separator: ",")
    }

    /// Quotes a field only when it needs it, keeping the common case readable.
    static func escapeCSV(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Renders a whole capture as CSV.
    static func csv(from records: [PacketRecord]) -> String {
        ([csvHeader] + records.map(\.csvRow)).joined(separator: "\n") + "\n"
    }
}
