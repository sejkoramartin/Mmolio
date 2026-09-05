//
//  PacketRecordTests.swift
//  MedProbeTests
//
//  Tests for the capture record: CSV serialisation, round-tripping, and the
//  positional framing fields.
//
//  The hex strings here are REAL frames captured from a Medtrum pump on 2026-09-05.
//  They are used only to check serialisation and positional extraction — no test in
//  this file asserts what any byte means, because that is not known.
//

import XCTest
@testable import MedProbe

final class PacketRecordTests: XCTestCase {

    private let characteristic9101 = "669A9101-0008-968F-E311-6050405558B3"

    private func data(_ hex: String) -> Data {
        Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
    }

    // MARK: - packet records

    func testPacketRecordCapturesLengthAndHex() {
        let frame = data("4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE")
        let record = PacketRecord.packet(
            timestamp: Date(timeIntervalSince1970: 1_757_000_000),
            characteristic: characteristic9101,
            data: frame
        )

        XCTAssertEqual(record.kind, .packet)
        XCTAssertEqual(record.length, 20)
        XCTAssertEqual(record.hex, "4F 93 3D 01 00 00 A0 8D D8 17 0B 00 A2 04 3F 02 9E 00 FF EE")
        XCTAssertEqual(record.characteristic, characteristic9101)
    }

    func testShortFrameIsRecordedFaithfully() {
        // 669A9120 frames are 13 bytes.
        let frame = data("20 22 10 00 58 00 45 07 02 88 01 46 0F")
        let record = PacketRecord.packet(timestamp: Date(), characteristic: "669A9120", data: frame)

        XCTAssertEqual(record.length, 13)
        XCTAssertEqual(record.hex.split(separator: " ").count, 13)
    }

    // MARK: - positional framing fields

    func testFramingFieldsReadBytesTwoAndThree() {
        let frame = data("4F 93 3D 04 00 02 06 04 00 02 03 01 00 02 00 02 00 02 03 D2")
        let record = PacketRecord.packet(timestamp: Date(), characteristic: characteristic9101, data: frame)

        // Purely positional: offset 2 and offset 3. No claim about meaning.
        XCTAssertEqual(record.byteAtOffset2, 0x3D)
        XCTAssertEqual(record.byteAtOffset3, 0x04)
        XCTAssertEqual(record.framingLabel, "3D/04")
    }

    func testFramingFieldsAreNilForVeryShortFrames() {
        let record = PacketRecord.packet(timestamp: Date(), characteristic: "X", data: data("20 22"))

        XCTAssertNil(record.byteAtOffset2)
        XCTAssertNil(record.byteAtOffset3)
        XCTAssertNil(record.framingLabel)
    }

    func testGroundTruthRowsHaveNoFramingLabel() {
        let record = PacketRecord.groundTruth(timestamp: Date(), mmoll: 10.6)
        XCTAssertNil(record.framingLabel)
    }

    // MARK: - ground truth

    func testGroundTruthRowUsesTheMarkerAndKeepsOneDecimal() {
        let stamp = Date(timeIntervalSince1970: 1_757_000_000)
        let record = PacketRecord.groundTruth(timestamp: stamp, mmoll: 10.6)

        XCTAssertEqual(record.kind, .groundTruth)
        XCTAssertEqual(record.characteristic, PacketRecord.groundTruthMarker)
        XCTAssertEqual(record.length, 0)
        XCTAssertEqual(record.hex, "10.6")
        XCTAssertEqual(record.timestamp, stamp)
    }

    // MARK: - CSV

    func testCSVHeaderIsExactlyTheRequestedColumns() {
        XCTAssertEqual(PacketRecord.csvHeader, "timestamp,characteristic,length,hex")
    }

    func testCSVRowHasFourFieldsAndMillisecondTimestamp() {
        let record = PacketRecord.packet(
            timestamp: Date(timeIntervalSince1970: 1_757_000_000.123),
            characteristic: characteristic9101,
            data: data("20 22 3E 01")
        )

        let fields = record.csvRow.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, 4)

        // Milliseconds must survive: several packets can land inside one second.
        XCTAssertTrue(record.csvRow.contains(".123"), "timestamp lost its milliseconds: \(record.csvRow)")
        XCTAssertEqual(String(fields[2]), "4")
    }

    func testCSVIncludesHeaderAndOneRowPerRecord() {
        let records = [
            PacketRecord.packet(timestamp: Date(), characteristic: "A", data: data("01 02")),
            PacketRecord.groundTruth(timestamp: Date(), mmoll: 6.4)
        ]

        let lines = PacketRecord.csv(from: records).split(separator: "\n")

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), PacketRecord.csvHeader)
        XCTAssertTrue(String(lines[2]).contains(PacketRecord.groundTruthMarker))
    }

    func testCSVEscapesOnlyWhenNeeded() {
        XCTAssertEqual(PacketRecord.escapeCSV("669A9141"), "669A9141")
        XCTAssertEqual(PacketRecord.escapeCSV("a,b"), "\"a,b\"")
        XCTAssertEqual(PacketRecord.escapeCSV("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testEmptyCaptureStillProducesAHeader() {
        XCTAssertEqual(PacketRecord.csv(from: []), PacketRecord.csvHeader + "\n")
    }

    // MARK: - persistence round trip

    func testRecordSurvivesJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = PacketRecord.packet(
            timestamp: Date(timeIntervalSince1970: 1_757_000_000),
            characteristic: characteristic9101,
            data: data("20 22 3E 02 17 03 4F 00 C8 00 E4 7F 83 00 1C 00 8E 1D")
        )

        let restored = try decoder.decode(PacketRecord.self, from: try encoder.encode(original))

        XCTAssertEqual(restored, original)
    }
}
