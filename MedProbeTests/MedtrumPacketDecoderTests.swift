//
//  MedtrumPacketDecoderTests.swift
//  MedProbeTests
//
//  Decoder tests. No CoreBluetooth, no radio, no device.
//
//  IMPORTANT — about the test data:
//  Every packet in this file is SYNTHETIC. It is assembled byte by byte to exercise the
//  decoder's arithmetic and validation, and it is NOT a captured real-world Medtrum packet.
//  The only values taken from the public xDrip4iOS reference implementation are the packet
//  layout (offsets), the 0x02 marker, and the observed calibration factors 8932 / 10333,
//  which that source documents as verified against EasyPatch ground truth. Nothing else here
//  claims to be real captured traffic.
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
