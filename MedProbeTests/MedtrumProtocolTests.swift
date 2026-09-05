//
//  MedtrumProtocolTests.swift
//  MedProbeTests
//
//  Two independent sources of truth:
//
//  1. The AndroidAPS Medtrum driver's own unit tests
//     (nightscout/AndroidAPS, NotificationPacketTest.kt). Those byte arrays are copied
//     here verbatim, converted from Kotlin's signed bytes, with the expected values that
//     project asserts. If our parser disagrees with them, our parser is wrong.
//
//  2. Frames captured from this pump on 2026-09-05, which are real traffic.
//
//  No test here asserts a meaning for the CGM field, because AndroidAPS does not decode
//  it and we have no evidence of our own yet.
//

import XCTest
@testable import MedProbe

final class MedtrumProtocolTests: XCTestCase {

    private func data(_ hex: String) -> Data {
        Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
    }

    private func parse(_ hex: String,
                       file: StaticString = #filePath,
                       line: UInt = #line) throws -> MedtrumNotification {
        switch MedtrumNotificationParser.parse(data(hex)) {
        case .success(let notification):
            return notification
        case .failure(let error):
            XCTFail("expected a parse, got \(error)", file: file, line: line)
            throw error
        }
    }

    private func field(_ notification: MedtrumNotification, _ mask: UInt16) -> NotificationField? {
        notification.fields.first { $0.mask == mask }
    }

    // MARK: - CRC-8 against real captured frames

    func testCrc8MatchesEveryCaptured9101Frame() {
        // Every 669A9101 frame captured on 2026-09-05. All must validate, or our
        // understanding of the framing is wrong.
        let captured = [
            "4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE",
            "4F 93 3D 02 00 01 64 00 06 64 00 00 00 40 0A 08 02 00 00 43",
            "4F 93 3D 03 00 00 00 00 02 07 03 00 02 06 04 00 02 05 03 C8",
            "4F 93 3D 04 00 02 06 04 00 02 03 01 00 02 00 02 00 02 03 D2",
            "4F 93 3D 05 01 00 12 00 00 00 02 00 00 00 00 00 00 00 FB 23",
            "4F 93 22 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 D1 DC",
            "4F 93 22 02 00 01 64 00 06 64 00 00 00 40 0A 07 02 00 00 42",
            "4F 93 22 03 00 00 00 00 02 07 03 00 02 06 04 00 02 05 03 EB",
            "20 22 3E 01 00 00 01 01 83 00 56 00 57 00 29 02 44 98 D8 CA",
            "20 22 3E 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 8E 1D",
            "20 22 3F 01 00 00 01 01 83 00 58 00 57 00 29 02 44 98 D8 06",
            "20 22 3F 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 CA D0",
            "20 22 21 01 00 00 01 01 83 00 22 00 57 00 29 02 44 98 D8 A4",
            "20 22 21 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 D3 81",
            "20 22 3C 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 69 5E",
            "20 22 40 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 C6 4B"
        ]

        for hex in captured {
            XCTAssertTrue(MedtrumCrc8.isFrameIntact(data(hex)), "checksum failed for \(hex)")
        }
    }

    func testCrc8RejectsACorruptedFrame() {
        var corrupted = data("20 22 3E 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 8E 1D")
        corrupted[5] ^= 0xFF

        XCTAssertFalse(MedtrumCrc8.isFrameIntact(corrupted))
    }

    // MARK: - AndroidAPS NotificationPacketTest, byte for byte

    func testAAPSBolusInProgressVector() throws {
        // AAPS: byteArrayOf(32, 34, 16, 0, 3, 0, -58, 12, 0, 0, 0, 0, 0)
        // asserts delivered 0.15 U, reservoir 163.5 U, bolus not done.
        let notification = try parse("20 22 10 00 03 00 C6 0C 00 00 00 00 00")

        XCTAssertEqual(notification.stateRaw, 0x20)
        XCTAssertEqual(notification.fieldMask, 0x1022)

        let bolus = field(notification, MedtrumNotificationParser.maskNormalBolus)
        XCTAssertEqual(bolus?.bytes, [0x00, 0x03, 0x00])
        XCTAssertEqual(bolus?.interpretation, "delivered 0.15 U, completed no")

        let reservoir = field(notification, MedtrumNotificationParser.maskReservoir)
        XCTAssertEqual(reservoir?.bytes, [0xC6, 0x0C])
        XCTAssertEqual(reservoir?.interpretation, "163.50 U")

        // AAPS carries a five-byte CGM field here and decodes none of it.
        XCTAssertEqual(notification.cgmFieldBytes, [0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(field(notification, MedtrumNotificationParser.maskUnusedCGM)?.interpretation)
    }

    func testAAPSBolusFinishedVector() throws {
        // AAPS: byteArrayOf(32, 34, 17, -128, 33, 0, -89, 12, -80, 0, 14, 0, 0, 0, 0, 0, 0)
        // asserts delivered 1.65 U, reservoir 161.95 U, bolus done.
        let notification = try parse("20 22 11 80 21 00 A7 0C B0 00 0E 00 00 00 00 00 00")

        XCTAssertEqual(notification.fieldMask, 0x1122)

        let bolus = field(notification, MedtrumNotificationParser.maskNormalBolus)
        XCTAssertEqual(bolus?.interpretation, "delivered 1.65 U, completed yes")

        let reservoir = field(notification, MedtrumNotificationParser.maskReservoir)
        XCTAssertEqual(reservoir?.interpretation, "161.95 U")

        // This mask also selects STORAGE, which sits between reservoir and CGM.
        XCTAssertNotNil(field(notification, MedtrumNotificationParser.maskStorage))
        XCTAssertEqual(notification.cgmFieldBytes, [0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testAAPSTooShortMessageIsRejected() {
        // AAPS: byteArrayOf(67, 41, 67, -1, 122, 95, 18, 0, 73, 1, 19, 0, 1, 0, 20, 0, 0, 0, 0, 16)
        // "given field mask but message too short then nothing saved".
        let result = MedtrumNotificationParser.parse(
            data("43 29 43 FF 7A 5F 12 00 49 01 13 00 01 00 14 00 00 00 00 10")
        )

        switch result {
        case .success:
            XCTFail("a message shorter than its field mask requires must not parse")
        case .failure(let error):
            guard case .truncated = error else {
                return XCTFail("expected .truncated, got \(error)")
            }
        }
    }

    func testFieldMaskLengthMatchesAAPSSizes() {
        // 0x1022 selects normal bolus (3) + reservoir (2) + CGM (5).
        XCTAssertEqual(MedtrumNotificationParser.expectedFieldLength(for: 0x1022), 10)
        // 0x1122 adds storage (4).
        XCTAssertEqual(MedtrumNotificationParser.expectedFieldLength(for: 0x1122), 14)
        XCTAssertEqual(MedtrumNotificationParser.expectedFieldLength(for: 0), 0)
    }

    // MARK: - our own captured 9120 frames

    func testCapturedFrameDecodesWithBolusAndReservoirConsistent() throws {
        // Two real frames, 12:47:29 and 12:51:06 on 2026-09-05, same bolus in progress.
        let earlier = try parse("20 22 10 00 22 00 7B 07 02 88 01 46 0F")
        let later = try parse("20 22 10 00 58 00 45 07 02 88 01 46 0F")

        XCTAssertEqual(earlier.fieldMask, 0x1022)
        XCTAssertEqual(later.fieldMask, 0x1022)

        // Independent physical cross-check: insulin that left the reservoir must equal
        // insulin the bolus delivered. This is what confirms the field offsets are right,
        // without relying on AAPS alone.
        let bolusEarlier = Double(UInt16(0x0022)) * 0.05
        let bolusLater = Double(UInt16(0x0058)) * 0.05
        let reservoirEarlier = Double(UInt16(0x077B)) * 0.05
        let reservoirLater = Double(UInt16(0x0745)) * 0.05

        XCTAssertEqual(bolusLater - bolusEarlier, reservoirEarlier - reservoirLater, accuracy: 0.001)

        XCTAssertEqual(earlier.fields.first { $0.mask == MedtrumNotificationParser.maskNormalBolus }?.interpretation,
                       "delivered 1.70 U, completed no")
        XCTAssertEqual(later.fields.first { $0.mask == MedtrumNotificationParser.maskReservoir }?.interpretation,
                       "93.05 U")
    }

    func testCapturedCGMFieldIsReportedButNotInterpreted() throws {
        let notification = try parse("20 22 10 00 58 00 45 07 02 88 01 46 0F")

        // The five bytes AAPS declines to decode. Recorded, deliberately not given meaning.
        XCTAssertEqual(notification.cgmFieldBytes, [0x02, 0x88, 0x01, 0x46, 0x0F])
        XCTAssertNil(field(notification, MedtrumNotificationParser.maskUnusedCGM)?.interpretation)
    }

    func testNotificationTooShortForAFieldMaskIsRejected() {
        switch MedtrumNotificationParser.parse(data("20 22")) {
        case .success: XCTFail("must not parse")
        case .failure(let error): XCTAssertEqual(error, .tooShort(actual: 2))
        }
    }

    // MARK: - 9101 fragment reassembly

    func testReassemblesTheCapturedFiveFragmentMessage() {
        let assembler = MedtrumFrameAssembler()
        let fragments = [
            "4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE",
            "4F 93 3D 02 00 01 64 00 06 64 00 00 00 40 0A 08 02 00 00 43",
            "4F 93 3D 03 00 00 00 00 02 07 03 00 02 06 04 00 02 05 03 C8",
            "4F 93 3D 04 00 02 06 04 00 02 03 01 00 02 00 02 00 02 03 D2",
            "4F 93 3D 05 01 00 12 00 00 00 02 00 00 00 00 00 00 00 FB 23"
        ]

        var completed: AssembledFrame?
        for (index, hex) in fragments.enumerated() {
            switch assembler.accept(data(hex)) {
            case .completed(let frame):
                XCTAssertEqual(index, fragments.count - 1, "completed early")
                completed = frame
            case .accumulating:
                XCTAssertLessThan(index, fragments.count - 1)
            case .discarded(let reason):
                XCTFail("fragment \(index + 1) discarded: \(reason)")
            }
        }

        let frame = try? XCTUnwrap(completed)
        XCTAssertEqual(frame?.declaredLength, 0x4F)
        XCTAssertEqual(frame?.fragmentCount, 5)
        XCTAssertEqual(frame?.isIntact, true)

        // 19 bytes from the first fragment, then 15 from each of the other four.
        XCTAssertEqual(frame?.payload.count, 19 + 15 * 4)
        XCTAssertGreaterThanOrEqual(frame?.payload.count ?? 0, 0x4F)
    }

    func testReassemblesTheCapturedTwoFragmentPair() {
        let assembler = MedtrumFrameAssembler()

        let first = assembler.accept(data("20 22 3E 01 00 00 01 01 83 00 56 00 57 00 29 02 44 98 D8 CA"))
        guard case .accumulating = first else {
            return XCTFail("first fragment should not complete the message: \(first)")
        }

        let second = assembler.accept(data("20 22 3E 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 8E 1D"))
        guard case .completed(let frame) = second else {
            return XCTFail("second fragment should complete the message: \(second)")
        }

        XCTAssertEqual(frame.declaredLength, 0x20)
        XCTAssertEqual(frame.fragmentCount, 2)
        XCTAssertTrue(frame.isIntact)
        XCTAssertEqual(frame.byteAtOffset2, 0x3E)
    }

    func testJoiningMidMessageIsDiscardedRatherThanMisassembled() {
        let assembler = MedtrumFrameAssembler()

        // A passive listener routinely starts watching partway through a message.
        let outcome = assembler.accept(data("4F 93 3D 03 00 00 00 00 02 07 03 00 02 06 04 00 02 05 03 C8"))

        guard case .discarded = outcome else {
            return XCTFail("a mid-message fragment must not start an assembly: \(outcome)")
        }
    }

    func testOutOfOrderFragmentIsDiscarded() {
        let assembler = MedtrumFrameAssembler()

        assembler.accept(data("4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE"))
        let outcome = assembler.accept(data("4F 93 3D 04 00 02 06 04 00 02 03 01 00 02 00 02 00 02 03 D2"))

        guard case .discarded(let reason) = outcome else {
            return XCTFail("a skipped fragment must be discarded: \(outcome)")
        }
        XCTAssertTrue(reason.contains("expected fragment 2"), reason)
    }

    func testFragmentOneAlwaysStartsAFreshMessage() {
        let assembler = MedtrumFrameAssembler()

        assembler.accept(data("4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE"))
        // A new message begins before the previous one finished; the old partial is dropped.
        let outcome = assembler.accept(data("20 22 3E 01 00 00 01 01 83 00 56 00 57 00 29 02 44 98 D8 CA"))

        guard case .accumulating(let fragmentCount, _, let need) = outcome else {
            return XCTFail("fragment 1 must start a new assembly: \(outcome)")
        }
        XCTAssertEqual(fragmentCount, 1)
        XCTAssertEqual(need, 0x20)
    }

    func testShortFragmentIsRejected() {
        let assembler = MedtrumFrameAssembler()

        guard case .discarded = assembler.accept(data("20 22 3E")) else {
            return XCTFail("a fragment too short to hold a header must be discarded")
        }
    }
}
