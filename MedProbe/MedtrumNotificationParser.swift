//
//  MedtrumNotificationParser.swift
//  MedProbe
//
//  READ-ONLY parser for notifications on characteristic 669A9120.
//
//  Semantics come from the AndroidAPS Medtrum driver
//  (nightscout/AndroidAPS, pump/medtrum/.../comm/packets/NotificationPacket.kt),
//  and are checked byte-for-byte against that project's own unit tests.
//
//  Frame layout:
//      byte 0      pump state
//      byte 1-2    field mask, uint16 little-endian
//      byte 3…     concatenated fields, in ascending mask-bit order
//
//  Parsing describes what the pump reported. It sends nothing, and this file contains
//  no command construction of any kind.
//

import Foundation

/// One field present in a notification, kept as raw bytes plus whatever AAPS knows about it.
struct NotificationField: Equatable {

    let mask: UInt16
    let name: String
    let bytes: [UInt8]

    /// Value decoded per AndroidAPS, when that project decodes this field at all.
    /// Nil where AAPS itself does not interpret the bytes — notably the CGM field.
    let interpretation: String?

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// A parsed 669A9120 notification.
struct MedtrumNotification: Equatable {

    /// Byte 0. AAPS maps this to a pump state enum; the raw value is kept here.
    let stateRaw: UInt8

    /// Bytes 1-2, little-endian.
    let fieldMask: UInt16

    let fields: [NotificationField]

    /// The five bytes AndroidAPS reserves as `MASK_UNUSED_CGM` and deliberately does not decode.
    /// This is the field MedProbe actually cares about; its meaning is not established.
    var cgmFieldBytes: [UInt8]? {
        fields.first { $0.mask == MedtrumNotificationParser.maskUnusedCGM }?.bytes
    }
}

enum MedtrumNotificationParseError: Error, Equatable {
    case tooShort(actual: Int)
    case truncated(expected: Int, actual: Int)
}

/// Decodes the field-mask notification format.
enum MedtrumNotificationParser {

    // MARK: - field masks (AndroidAPS NotificationPacket.kt)

    static let maskSuspend: UInt16 = 0x0001
    static let maskNormalBolus: UInt16 = 0x0002
    static let maskExtendedBolus: UInt16 = 0x0004
    static let maskBasal: UInt16 = 0x0008
    static let maskSetup: UInt16 = 0x0010
    static let maskReservoir: UInt16 = 0x0020
    static let maskStartTime: UInt16 = 0x0040
    static let maskBattery: UInt16 = 0x0080
    static let maskStorage: UInt16 = 0x0100
    static let maskAlarm: UInt16 = 0x0200
    static let maskAge: UInt16 = 0x0400
    static let maskMagnetoPlace: UInt16 = 0x0800

    /// AndroidAPS calls this MASK_UNUSED_CGM: it knows the field exists and is five bytes
    /// wide, logs it, and does not decode it. "Unused" means unused *by AAPS*.
    static let maskUnusedCGM: UInt16 = 0x1000

    static let maskUnusedCommandConfirm: UInt16 = 0x2000
    static let maskUnusedAutoStatus: UInt16 = 0x4000
    static let maskUnusedLegacy: UInt16 = 0x8000

    /// Mask, field name and byte width, in the order AndroidAPS lays them out.
    /// Order matters: fields are concatenated in this sequence, so a wrong width here
    /// silently shifts every field after it.
    static let fieldTable: [(mask: UInt16, name: String, size: Int)] = [
        (maskSuspend, "suspend", 4),
        (maskNormalBolus, "normalBolus", 3),
        (maskExtendedBolus, "extendedBolus", 3),
        (maskBasal, "basal", 12),
        (maskSetup, "setup", 1),
        (maskReservoir, "reservoir", 2),
        (maskStartTime, "startTime", 4),
        (maskBattery, "battery", 3),
        (maskStorage, "storage", 4),
        (maskAlarm, "alarm", 4),
        (maskAge, "age", 4),
        (maskMagnetoPlace, "magnetoPlace", 2),
        (maskUnusedCGM, "CGM (undecoded by AAPS)", 5),
        (maskUnusedCommandConfirm, "commandConfirm", 2),
        (maskUnusedAutoStatus, "autoStatus", 2),
        (maskUnusedLegacy, "legacy", 2)
    ]

    private static let fieldMaskSize = 2

    // MARK: - parsing

    static func parse(_ data: Data) -> Result<MedtrumNotification, MedtrumNotificationParseError> {

        // state byte + field mask
        guard data.count > 1 + fieldMaskSize else {
            return .failure(.tooShort(actual: data.count))
        }

        let bytes = [UInt8](data)
        let stateRaw = bytes[0]
        let fieldMask = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)

        let expected = 1 + fieldMaskSize + expectedFieldLength(for: fieldMask)
        guard bytes.count >= expected else {
            return .failure(.truncated(expected: expected, actual: bytes.count))
        }

        var offset = 1 + fieldMaskSize
        var fields: [NotificationField] = []

        for entry in fieldTable where fieldMask & entry.mask != 0 {
            let slice = Array(bytes[offset ..< offset + entry.size])
            fields.append(
                NotificationField(
                    mask: entry.mask,
                    name: entry.name,
                    bytes: slice,
                    interpretation: interpret(mask: entry.mask, bytes: slice)
                )
            )
            offset += entry.size
        }

        return .success(MedtrumNotification(stateRaw: stateRaw, fieldMask: fieldMask, fields: fields))
    }

    /// Total width of the fields a mask selects, excluding the mask itself.
    static func expectedFieldLength(for fieldMask: UInt16) -> Int {
        fieldTable.reduce(0) { total, entry in
            fieldMask & entry.mask != 0 ? total + entry.size : total
        }
    }

    // MARK: - interpretation
    //
    // Only fields AndroidAPS itself decodes get an interpretation. Everything else is
    // reported as raw bytes. The CGM field deliberately gets none: AAPS does not decode
    // it, so any meaning assigned here would be invention.

    private static func interpret(mask: UInt16, bytes: [UInt8]) -> String? {
        switch mask {
        case maskNormalBolus:
            // AAPS: byte 0 low 7 bits = type, bit 7 = completed, bytes 1-2 = delivered * 0.05
            guard bytes.count == 3 else { return nil }
            let completed = (bytes[0] >> 7) & 0x01 != 0
            let delivered = Double(uint16LE(bytes, 1)) * 0.05
            return String(format: "delivered %.2f U, completed %@", delivered, completed ? "yes" : "no")

        case maskReservoir:
            guard bytes.count == 2 else { return nil }
            return String(format: "%.2f U", Double(uint16LE(bytes, 0)) * 0.05)

        case maskUnusedCGM:
            // AndroidAPS logs these five bytes and does nothing with them. Neither do we.
            return nil

        default:
            return nil
        }
    }

    private static func uint16LE(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }
}
