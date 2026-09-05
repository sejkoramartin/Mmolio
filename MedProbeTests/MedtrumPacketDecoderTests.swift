//
//  MedtrumPacketDecoderTests.swift
//  MedProbeTests
//
//  Decoder tests. No CoreBluetooth, no radio, no device.
//
//  IMPORTANT — about the test data, which is now of two kinds:
//
//  1. SYNTHETIC frames, built byte by byte by makeSyntheticPacket, used to exercise the
//     arithmetic and the validation rules. These are not captured traffic and do not
//     claim to be. Their layout comes from the xDrip4iOS reference implementation, as do
//     the 0x02 marker and the calibration factors 8932 / 10333.
//
//  2. REAL packets, in the final extension, captured from this pump on 2026-09-05 along
//     with the values EasyPatch displayed at the same time. These are the project's only
//     ground truth and are asserted precisely.
//
//  Keep the two clearly separated: a synthetic frame proves the code does what we told it
//  to, and only a real one proves we told it the right thing.
//

import XCTest
@testable import MedProbe

final class MedtrumPacketDecoderTests: XCTestCase {

    // MARK: - synthetic packet construction

    /// Builds a 20-byte packet with the documented fields set and everything else zeroed.
    ///
    /// SYNTHETIC — see the file header.
    private func makeSyntheticPacket(marker: UInt8 = 0x02,
                                     counter: UInt16 = 1234,
                                     rawGlucose: UInt16 = 1027,
                                     history: [UInt16] = [1020, 1015, 1010],
                                     calibrationFactor: UInt16 = 8932) -> Data {

        var bytes = [UInt8](repeating: 0, count: 20)

        bytes[0] = 0xB3          // packet type high byte, as observed in the reference implementation
        bytes[1] = marker

        func writeUInt16LE(_ value: UInt16, at offset: Int) {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        }

        writeUInt16LE(counter, at: 4)
        writeUInt16LE(rawGlucose, at: 8)
        writeUInt16LE(history[0], at: 10)
        writeUInt16LE(history[1], at: 12)
        writeUInt16LE(history[2], at: 14)
        writeUInt16LE(calibrationFactor, at: 18)

        return Data(bytes)
    }

    private func expectSuccess(_ result: Result<MedtrumReading, MedtrumDecodeError>,
                               file: StaticString = #filePath,
                               line: UInt = #line) throws -> MedtrumReading {
        switch result {
        case .success(let reading):
            return reading
        case .failure(let error):
            XCTFail("expected success, got \(error.localizedDescription)", file: file, line: line)
            throw error
        }
    }

    private func expectFailure(_ result: Result<MedtrumReading, MedtrumDecodeError>,
                               file: StaticString = #filePath,
                               line: UInt = #line) -> MedtrumDecodeError? {
        switch result {
        case .success(let reading):
            XCTFail("expected failure, decoded \(reading.mgdl) mg/dL", file: file, line: line)
            return nil
        case .failure(let error):
            return error
        }
    }

    // MARK: - happy path

    func testDecodesWellFormedPacket() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let packet = makeSyntheticPacket()

        let reading = try expectSuccess(MedtrumPacketDecoder.decode(packet, receivedAt: timestamp))

        XCTAssertEqual(reading.counter, 1234)
        XCTAssertEqual(reading.rawGlucose, 1027)
        XCTAssertEqual(reading.calibrationFactor, 8932)
        XCTAssertEqual(reading.receivedAt, timestamp)
        XCTAssertEqual(reading.historyRawGlucose, [1020, 1015, 1010])

        // 1027 * 1000 / 8932
        XCTAssertEqual(reading.mgdl, 114.9798, accuracy: 0.01)
    }

    func testHexRepresentationCoversWholePacket() throws {
        let reading = try expectSuccess(MedtrumPacketDecoder.decode(makeSyntheticPacket()))

        let components = reading.rawPacketHex.split(separator: " ")
        XCTAssertEqual(components.count, 20)
        XCTAssertTrue(reading.rawPacketHex.hasPrefix("B3 02"))
    }

    // MARK: - length validation

    func testRejectsShortPacket() {
        let short = makeSyntheticPacket().prefix(19)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(Data(short))) else { return }
        XCTAssertEqual(error, .invalidLength(actual: 19))
    }

    func testRejectsLongPacket() {
        var long = makeSyntheticPacket()
        long.append(0x00)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(long)) else { return }
        XCTAssertEqual(error, .invalidLength(actual: 21))
    }

    func testRejectsEmptyPacket() {
        guard let error = expectFailure(MedtrumPacketDecoder.decode(Data())) else { return }
        XCTAssertEqual(error, .invalidLength(actual: 0))
    }

    // MARK: - marker validation

    func testRejectsWrongPacketMarker() {
        let packet = makeSyntheticPacket(marker: 0x05)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(packet)) else { return }
        XCTAssertEqual(error, .invalidPacketMarker(actual: 0x05))
    }

    // MARK: - calibration factor validation

    func testRejectsZeroCalibrationFactor() {
        let packet = makeSyntheticPacket(calibrationFactor: 0)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(packet)) else { return }
        XCTAssertEqual(error, .zeroCalibrationFactor)
    }

    // MARK: - plausibility window

    func testRejectsGlucoseBelowWindow() {
        // 39 * 1000 / 1000 = 39 mg/dL
        let packet = makeSyntheticPacket(rawGlucose: 39, calibrationFactor: 1000)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(packet)) else { return }
        XCTAssertEqual(error, .implausibleGlucose(mgdl: 39))
    }

    func testRejectsGlucoseAboveWindow() {
        // 401 * 1000 / 1000 = 401 mg/dL
        let packet = makeSyntheticPacket(rawGlucose: 401, calibrationFactor: 1000)

        guard let error = expectFailure(MedtrumPacketDecoder.decode(packet)) else { return }
        XCTAssertEqual(error, .implausibleGlucose(mgdl: 401))
    }

    func testAcceptsGlucoseExactlyAtWindowBounds() throws {
        let low = try expectSuccess(
            MedtrumPacketDecoder.decode(makeSyntheticPacket(rawGlucose: 40, calibrationFactor: 1000))
        )
        XCTAssertEqual(low.mgdl, 40, accuracy: 0.0001)

        let high = try expectSuccess(
            MedtrumPacketDecoder.decode(makeSyntheticPacket(rawGlucose: 400, calibrationFactor: 1000))
        )
        XCTAssertEqual(high.mgdl, 400, accuracy: 0.0001)
    }

    // MARK: - little-endian decoding

    func testDecodesLittleEndianFieldsFromExplicitBytes() throws {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0xB3
        bytes[1] = 0x02
        bytes[4] = 0x34; bytes[5] = 0x12    // counter            0x1234 = 4660
        bytes[8] = 0x03; bytes[9] = 0x04    // current raw        0x0403 = 1027
        bytes[10] = 0xFC; bytes[11] = 0x03  // history 2 min ago  0x03FC = 1020
        bytes[12] = 0xF7; bytes[13] = 0x03  // history 4 min ago  0x03F7 = 1015
        bytes[14] = 0xF2; bytes[15] = 0x03  // history 6 min ago  0x03F2 = 1010
        bytes[18] = 0xE4; bytes[19] = 0x22  // calibration factor 0x22E4 = 8932

        let reading = try expectSuccess(MedtrumPacketDecoder.decode(Data(bytes)))

        XCTAssertEqual(reading.counter, 4660)
        XCTAssertEqual(reading.rawGlucose, 1027)
        XCTAssertEqual(reading.calibrationFactor, 8932)
        XCTAssertEqual(reading.historyRawGlucose, [1020, 1015, 1010])
    }

    func testDecodingIsIndependentOfDataSliceStartIndex() throws {
        // Data handed over by CoreBluetooth can be a slice whose startIndex is not 0.
        var padded = Data([0xFF, 0xFF, 0xFF])
        padded.append(makeSyntheticPacket())
        let slice = padded.dropFirst(3)

        XCTAssertEqual(slice.count, 20)
        XCTAssertNotEqual(slice.startIndex, 0)

        let reading = try expectSuccess(MedtrumPacketDecoder.decode(slice))

        XCTAssertEqual(reading.counter, 1234)
        XCTAssertEqual(reading.rawGlucose, 1027)
        XCTAssertEqual(reading.calibrationFactor, 8932)
    }

    // MARK: - unit conversion

    func testConvertsMgdlToMmoll() throws {
        let reading = try expectSuccess(MedtrumPacketDecoder.decode(makeSyntheticPacket()))

        // 114.979 / 18.0182
        XCTAssertEqual(reading.mmoll, 6.3813, accuracy: 0.005)
        XCTAssertEqual(reading.mgdl / 18.0182, reading.mmoll, accuracy: 0.000001)
    }

    func testConversionAtASecondDocumentedCalibrationFactor() throws {
        // 10333 is the second calibration factor documented in the xDrip4iOS reference.
        // The packet carrying it here is still synthetic.
        let packet = makeSyntheticPacket(rawGlucose: 1200, calibrationFactor: 10333)

        let reading = try expectSuccess(MedtrumPacketDecoder.decode(packet))

        XCTAssertEqual(reading.mgdl, 116.1328, accuracy: 0.01)
        XCTAssertEqual(reading.mmoll, 6.4453, accuracy: 0.005)
    }

    // MARK: - history conversion

    func testHistoryValuesUseTheSameCalibrationFactor() throws {
        let reading = try expectSuccess(MedtrumPacketDecoder.decode(makeSyntheticPacket()))

        XCTAssertEqual(reading.historyMgdl.count, 3)
        XCTAssertEqual(reading.historyMgdl[0], 1020.0 * 1000.0 / 8932.0, accuracy: 0.0001)
        XCTAssertEqual(reading.historyMgdl[2], 1010.0 * 1000.0 / 8932.0, accuracy: 0.0001)
    }
}

// MARK: - real packets verified against EasyPatch
//
// Unlike the synthetic frames above, these four are REAL 669A9141 packets captured on
// 2026-09-05 between 11:42 and 11:48, alongside the values EasyPatch displayed at the
// time. They are the only ground truth in this project, so they are asserted precisely.

extension MedtrumPacketDecoderTests {

    private func realPacket(_ hex: String) -> Data {
        Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
    }

    func testRealPacketsMatchEasyPatchToWithinRounding() throws {
        // packet hex, and the mmol/L EasyPatch showed for that cycle
        let captures: [(hex: String, easyPatch: Double)] = [
            ("6F 06 0A 27 1E 15 4D 00 33 01 33 01 32 01 35 01 00 00 0D 04", 16.4),
            ("6F 06 0A 27 1F 15 4D 00 32 01 33 01 33 01 32 01 00 00 0D 04", 16.4),
            ("6F 06 0A 27 20 15 4D 00 34 01 32 01 33 01 33 01 00 00 0D 04", 16.5)
        ]

        for capture in captures {
            let reading = try expectSuccess(MedtrumPacketDecoder.decode(realPacket(capture.hex)))

            // EasyPatch rounds to one decimal, so agreement to 0.05 mmol/L is as close as
            // this comparison can get.
            XCTAssertEqual(reading.mmoll, capture.easyPatch, accuracy: 0.05,
                           "decoded \(reading.mmoll) mmol/L, EasyPatch showed \(capture.easyPatch)")
        }
    }

    func testRealPacketFieldsDecodeAsExpected() throws {
        let reading = try expectSuccess(
            MedtrumPacketDecoder.decode(realPacket("6F 06 0A 27 1D 15 4D 00 33 01 32 01 35 01 33 01 00 00 0D 04"))
        )

        XCTAssertEqual(reading.counter, 0x151D)             // 5405
        XCTAssertEqual(reading.rawGlucose, 0x0133)          // 307
        XCTAssertEqual(reading.calibrationFactor, 0x040D)   // 1037
        XCTAssertEqual(reading.mgdl, 296.05, accuracy: 0.01)
        XCTAssertEqual(reading.mmoll, 16.43, accuracy: 0.01)
        XCTAssertEqual(reading.historyRawGlucose, [306, 309, 307])

        // 5405 cycles x 2 minutes, on a 14-day sensor.
        XCTAssertEqual(reading.sensorAge / 3600, 180.2, accuracy: 0.1)
    }

    func testThisPumpsMarkerByteIsAccepted() throws {
        // 0x06, not the 0x02 the xDrip reference documents. Rejecting it is what kept
        // glucose off the screen even though the packets were arriving.
        let reading = try expectSuccess(
            MedtrumPacketDecoder.decode(realPacket("6F 06 0A 27 1D 15 4D 00 33 01 32 01 35 01 33 01 00 00 0D 04"))
        )
        XCTAssertGreaterThan(reading.mgdl, 0)

        // The documented marker still works.
        XCTAssertTrue(MedtrumPacketDecoder.cgmPacketMarkers.contains(0x02))
        XCTAssertTrue(MedtrumPacketDecoder.cgmPacketMarkers.contains(0x06))
    }

    func testUnknownMarkerIsStillRejected() {
        // Widening the marker set must not turn into accepting anything.
        var packet = [UInt8](realPacket("6F 06 0A 27 1D 15 4D 00 33 01 32 01 35 01 33 01 00 00 0D 04"))
        packet[1] = 0x09

        guard let error = expectFailure(MedtrumPacketDecoder.decode(Data(packet))) else { return }
        XCTAssertEqual(error, .invalidPacketMarker(actual: 0x09))
    }

    func testConsecutiveRealPacketsShowTheHistoryShifting() throws {
        // Each packet's first history slot should hold the previous packet's current value.
        // This is what confirms offsets 8 and 10 are a current/previous pair.
        let first = try expectSuccess(
            MedtrumPacketDecoder.decode(realPacket("6F 06 0A 27 1E 15 4D 00 33 01 33 01 32 01 35 01 00 00 0D 04"))
        )
        let second = try expectSuccess(
            MedtrumPacketDecoder.decode(realPacket("6F 06 0A 27 1F 15 4D 00 32 01 33 01 33 01 32 01 00 00 0D 04"))
        )

        XCTAssertEqual(second.counter, first.counter + 1)
        XCTAssertEqual(second.historyRawGlucose[0], first.rawGlucose)
    }
}
