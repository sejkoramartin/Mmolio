//
//  GarminMessageTests.swift
//  MedProbeTests
//
//  Wire format and send policy. The watch has its own decoder in Monkey C; these tests
//  pin the format both sides must agree on.
//

import XCTest
@testable import MedProbe

final class GarminMessageTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)

    private func reading(mgdl: Double = 296.05,
                         at offset: TimeInterval = 0,
                         trend: GlucoseTrend = .risingSlightly,
                         source: GlucoseSourceKind = .medtrum,
                         sequence: Int = 5469) -> GlucoseReading {
        GlucoseReading(mgdl: mgdl,
                       measuredAt: epoch.addingTimeInterval(offset),
                       trend: trend,
                       source: source,
                       sequence: sequence)
    }

    // MARK: - encoding

    func testEncodedMessageCarriesEveryRequiredField() {
        let payload = GarminMessage(reading: reading()).encoded()

        XCTAssertEqual(payload[GarminMessage.Key.version] as? Int, 1)
        XCTAssertEqual(payload[GarminMessage.Key.mgdl] as? Int, 296)
        XCTAssertEqual(payload[GarminMessage.Key.trend] as? Int, GlucoseTrend.risingSlightly.wireValue)
        XCTAssertEqual(payload[GarminMessage.Key.measuredAt] as? Int, Int(epoch.timeIntervalSince1970))
        XCTAssertEqual(payload[GarminMessage.Key.source] as? Int, GlucoseSourceKind.medtrum.wireValue)
        XCTAssertEqual(payload[GarminMessage.Key.sequence] as? Int, 5469)
    }

    func testGlucoseIsRoundedNotTruncated() {
        XCTAssertEqual(GarminMessage(reading: reading(mgdl: 296.7)).encoded()[GarminMessage.Key.mgdl] as? Int, 297)
        XCTAssertEqual(GarminMessage(reading: reading(mgdl: 296.2)).encoded()[GarminMessage.Key.mgdl] as? Int, 296)
    }

    func testPayloadStaysSmall() {
        // Connect IQ transfers are size-limited and cost battery on both ends.
        let payload = GarminMessage(reading: reading()).encoded()
        XCTAssertEqual(payload.count, 6)
        for key in payload.keys {
            XCTAssertEqual(key.count, 1, "key '\(key)' should be a single character")
        }
    }

    // MARK: - decoding

    func testRoundTripPreservesEveryField() throws {
        let original = GarminMessage(reading: reading(trend: .fallingQuickly, source: .libreLinkUp, sequence: 42))

        let decoded = try GarminMessage.decode(original.encoded()).get()

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.mgdl, original.mgdl.rounded(), accuracy: 0.001)
        XCTAssertEqual(decoded.trend, .fallingQuickly)
        XCTAssertEqual(decoded.source, .libreLinkUp)
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.measuredAt.timeIntervalSince1970,
                       original.measuredAt.timeIntervalSince1970, accuracy: 1)
    }

    func testUnknownVersionIsRejectedRatherThanGuessed() {
        var payload = GarminMessage(reading: reading()).encoded()
        payload[GarminMessage.Key.version] = 99

        let result = GarminMessage.decode(payload)
        if case .failure(let error) = result {
            XCTAssertEqual(error, .unsupportedVersion(99))
        } else {
            XCTFail("a message from a newer protocol must not be interpreted")
        }
    }

    func testEveryMissingFieldIsReportedByName() {
        let keys = [GarminMessage.Key.version, GarminMessage.Key.mgdl, GarminMessage.Key.trend,
                    GarminMessage.Key.measuredAt, GarminMessage.Key.source, GarminMessage.Key.sequence]

        for key in keys {
            var payload = GarminMessage(reading: reading()).encoded()
            payload.removeValue(forKey: key)

            let result = GarminMessage.decode(payload)
            if case .failure(let error) = result {
                XCTAssertEqual(error, .missingField(key))
            } else {
                XCTFail("missing '\(key)' should not decode")
            }
        }
    }

    // MARK: - send policy

    func testFirstReadingIsSent() {
        var policy = GarminSendPolicy()
        XCTAssertEqual(policy.decide(reading()), .send)
    }

    func testDuplicateSequenceIsNotResent() {
        var policy = GarminSendPolicy()
        _ = policy.decide(reading(sequence: 100))

        XCTAssertEqual(policy.decide(reading(at: 120, sequence: 100)), .skipDuplicate)
    }

    func testOlderSequenceIsNotSent() {
        var policy = GarminSendPolicy()
        _ = policy.decide(reading(sequence: 100))

        XCTAssertEqual(policy.decide(reading(at: 120, sequence: 99)), .skipOlder)
    }

    func testOlderTimestampIsNotSentEvenWithAHigherSequence() {
        var policy = GarminSendPolicy()
        _ = policy.decide(reading(at: 0, sequence: 100))

        XCTAssertEqual(policy.decide(reading(at: -600, sequence: 101)), .skipOlder)
    }

    func testNewerReadingIsSent() {
        var policy = GarminSendPolicy()
        _ = policy.decide(reading(sequence: 100))

        XCTAssertEqual(policy.decide(reading(at: 120, sequence: 101)), .send)
    }

    func testSwitchingSourceResetsTheComparison() {
        var policy = GarminSendPolicy()
        // Medtrum counters run in the thousands; a Libre sequence would look ancient
        // beside them, and the first reading after a switch must not be discarded.
        _ = policy.decide(reading(source: .medtrum, sequence: 5469))

        XCTAssertEqual(policy.decide(reading(at: 120, source: .libreLinkUp, sequence: 3)), .send)
    }

    // MARK: - transport stand-in

    func testUnavailableTransportStillAppliesThePolicyAndReportsTheMissingSDK() {
        let transport = UnavailableGarminTransport()
        var results: [Result<Void, GarminTransportError>] = []

        transport.send(reading(sequence: 1)) { results.append($0) }
        transport.send(reading(at: 120, sequence: 1)) { results.append($0) }   // duplicate
        transport.send(reading(at: 240, sequence: 2)) { results.append($0) }

        // Two distinct readings passed the policy; the duplicate did not.
        XCTAssertEqual(transport.acceptedMessages.count, 2)
        XCTAssertEqual(transport.acceptedMessages.map(\.sequence), [1, 2])

        // A skipped duplicate is not an error; a genuine send fails because the SDK is absent.
        if case .failure(let error) = results[0] { XCTAssertEqual(error, .sdkUnavailable) }
        else { XCTFail("expected the missing SDK to be reported") }
        XCTAssertNoThrow(try results[1].get(), "a suppressed duplicate is not a failure")
    }

    func testKnownSupportedModelsAreRecognised() {
        XCTAssertTrue(GarminDevice(id: 1, name: "Forerunner 255", isConnected: true).isKnownSupported)
        XCTAssertTrue(GarminDevice(id: 2, name: "Forerunner 165 Music", isConnected: true).isKnownSupported)
        XCTAssertFalse(GarminDevice(id: 3, name: "Fenix 7", isConnected: true).isKnownSupported)
    }
}

// MARK: - device identity
//
// The selected watch is remembered across launches, so whatever identifies it has to
// survive a restart. Swift seeds hashing per process, which hashValue does not.

extension GarminMessageTests {

    /// Same derivation ConnectIQTransport uses: the first eight bytes of the UUID.
    private func identity(of uuid: UUID) -> UInt64 {
        withUnsafeBytes(of: uuid.uuid) { raw in
            raw.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
    }

    func testDeviceIdentityIsDerivedFromTheUUIDAndIsStable() {
        let uuid = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!

        // Deterministic: the same UUID must give the same id in any process.
        XCTAssertEqual(identity(of: uuid), identity(of: uuid))
        XCTAssertEqual(identity(of: uuid), 0x123456789ABCDEF0)
    }

    func testDifferentWatchesGetDifferentIdentities() {
        let first = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!
        let second = UUID(uuidString: "22345678-9ABC-DEF0-1234-56789ABCDEF0")!

        XCTAssertNotEqual(identity(of: first), identity(of: second))
    }

    func testIdentitySurvivesStorageAsASignedInteger() {
        // UserDefaults stores Int, so a large UInt64 has to round-trip through the bit
        // pattern rather than being clamped.
        let original = identity(of: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-1234-56789ABCDEF0")!)

        let stored = Int64(bitPattern: original)
        let restored = UInt64(bitPattern: stored)

        XCTAssertEqual(restored, original)
        XCTAssertGreaterThan(original, UInt64(Int64.max), "this value needs the full range")
    }
}
