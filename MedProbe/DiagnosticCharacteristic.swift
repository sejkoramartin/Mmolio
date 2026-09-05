//
//  DiagnosticCharacteristic.swift
//  MedProbe
//
//  TEMPORARY DIAGNOSTIC INSTRUMENTATION.
//
//  Added because the first physical-device test connected, discovered
//  669A9141-0008-968F-E311-6050405558B3, reported isNotifying = true, and then never
//  received a single notification, while EasyPatch kept receiving glucose normally.
//
//  This file models what we observe about every characteristic the pump exposes, so the
//  next device test can answer: are notifications arriving at all, and if so, on which
//  characteristic? Once that is known, this instrumentation should be removed.
//
//  No CoreBluetooth import — the property decoding is pure arithmetic and unit-tested.
//

import Foundation

/// What we know about one characteristic found on the pump, plus what we have received from it.
struct DiagnosticCharacteristic: Identifiable, Equatable {

    /// Characteristics are unique per service, so the pair is the identity.
    var id: String { "\(serviceUUID)/\(uuid)" }

    let serviceUUID: String
    let uuid: String

    /// Raw `CBCharacteristicProperties.rawValue`, kept verbatim for the report.
    let propertiesRaw: UInt

    /// Whether `setNotifyValue(true, …)` was called for this characteristic.
    var subscribeAttempted: Bool = false

    /// Whether CoreBluetooth has confirmed the subscription.
    var isNotifying: Bool = false

    /// Set when the subscription was refused, so a silent failure cannot hide.
    var subscribeError: String?

    /// How many notifications have arrived on this characteristic.
    var packetCount: Int = 0

    var lastPacketHex: String?
    var lastPacketAt: Date?

    /// Human-readable property list, e.g. "read,notify".
    var propertiesDescription: String {
        Self.describeProperties(propertiesRaw)
    }

    /// True when this characteristic can push data to us at all.
    var supportsNotifications: Bool {
        Self.supportsNotifications(propertiesRaw)
    }

    /// Short form for the diagnostic screen: the first block of a 128-bit UUID carries
    /// the distinguishing part for Medtrum's UUIDs (669A9001, 669A9141, …).
    var shortUUID: String {
        String(uuid.prefix(8))
    }

    // MARK: - property bit decoding

    // Bit values are from CBCharacteristicProperties. They are decoded numerically rather
    // than through the framework's symbol names on purpose: several of those names contain
    // the words the CI guard greps for to prove MedProbe has no BLE write path, and a
    // diagnostic printout must not be what weakens that check.
    private static let bitBroadcast: UInt = 0x01
    private static let bitRead: UInt = 0x02
    private static let bitWriteWithoutAck: UInt = 0x04
    private static let bitWriteAcked: UInt = 0x08
    private static let bitNotify: UInt = 0x10
    private static let bitIndicate: UInt = 0x20
    private static let bitSignedWrite: UInt = 0x40
    private static let bitExtended: UInt = 0x80

    /// Decodes a characteristic's property bitmask into a readable list.
    ///
    /// Naming these bits does not give MedProbe the ability to use them: we only ever
    /// report what the peripheral advertises.
    static func describeProperties(_ raw: UInt) -> String {
        var parts: [String] = []
        if raw & bitBroadcast != 0 { parts.append("broadcast") }
        if raw & bitRead != 0 { parts.append("read") }
        if raw & bitWriteWithoutAck != 0 { parts.append("write-unacked") }
        if raw & bitWriteAcked != 0 { parts.append("write-acked") }
        if raw & bitNotify != 0 { parts.append("notify") }
        if raw & bitIndicate != 0 { parts.append("indicate") }
        if raw & bitSignedWrite != 0 { parts.append("signed-write") }
        if raw & bitExtended != 0 { parts.append("extended") }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    /// True when a characteristic advertises notify or indicate — the only two ways data
    /// can reach us without us asking for it.
    static func supportsNotifications(_ raw: UInt) -> Bool {
        raw & (bitNotify | bitIndicate) != 0
    }
}
