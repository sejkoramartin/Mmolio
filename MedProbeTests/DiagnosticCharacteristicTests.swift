//
//  DiagnosticCharacteristicTests.swift
//  MedProbeTests
//
//  Tests for the characteristic property decoding used by the diagnostic build.
//  Pure arithmetic, no CoreBluetooth.
//

import XCTest
@testable import MedProbe

final class DiagnosticCharacteristicTests: XCTestCase {

    // MARK: - property decoding

    func testDecodesTheValueObservedOnTheRealPump() {
        // The physical iPhone test logged "properties 16" for 669A9141, i.e. notify only:
        // no read bit, and crucially no write bit of any kind.
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(16), "notify")
        XCTAssertTrue(DiagnosticCharacteristic.supportsNotifications(16))
    }

    func testDecodesIndividualBits() {
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x01), "broadcast")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x02), "read")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x04), "write-unacked")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x08), "write-acked")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x10), "notify")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x20), "indicate")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x40), "signed-write")
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x80), "extended")
    }

    func testDecodesCombinedBitsInOrder() {
        // read + notify
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x12), "read,notify")
        // read + write-acked + notify
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0x1A), "read,write-acked,notify")
    }

    func testDecodesEmptyMask() {
        XCTAssertEqual(DiagnosticCharacteristic.describeProperties(0), "none")
    }

    // MARK: - notification capability

    func testNotifyAndIndicateBothCountAsNotificationCapable() {
        XCTAssertTrue(DiagnosticCharacteristic.supportsNotifications(0x10))   // notify
        XCTAssertTrue(DiagnosticCharacteristic.supportsNotifications(0x20))   // indicate
        XCTAssertTrue(DiagnosticCharacteristic.supportsNotifications(0x30))   // both
        XCTAssertTrue(DiagnosticCharacteristic.supportsNotifications(0x12))   // read + notify
    }

    func testCharacteristicsWithoutNotifyOrIndicateAreNotSubscribable() {
        XCTAssertFalse(DiagnosticCharacteristic.supportsNotifications(0x00))
        XCTAssertFalse(DiagnosticCharacteristic.supportsNotifications(0x02))  // read only
        XCTAssertFalse(DiagnosticCharacteristic.supportsNotifications(0x0A))  // read + write
        XCTAssertFalse(DiagnosticCharacteristic.supportsNotifications(0x8F))  // everything but notify/indicate
    }

    // MARK: - identity and display

    func testIdentityCombinesServiceAndCharacteristic() {
        let a = DiagnosticCharacteristic(serviceUUID: "S1", uuid: "C1", propertiesRaw: 0x10)
        let b = DiagnosticCharacteristic(serviceUUID: "S2", uuid: "C1", propertiesRaw: 0x10)

        // Same characteristic UUID under two services must not collapse into one row.
        XCTAssertNotEqual(a.id, b.id)
    }

    func testShortUUIDKeepsTheDistinguishingPrefix() {
        let entry = DiagnosticCharacteristic(
            serviceUUID: "669A9001-0008-968F-E311-6050405558B3",
            uuid: "669A9141-0008-968F-E311-6050405558B3",
            propertiesRaw: 0x10
        )

        XCTAssertEqual(entry.shortUUID, "669A9141")
    }
}
