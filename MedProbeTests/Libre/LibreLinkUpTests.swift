//
//  LibreLinkUpTests.swift
//  MedProbeTests
//
//  Parsing, normalisation, credential storage and the re-authentication path.
//
//  No real account details anywhere: every credential here is obviously fake.
//

import XCTest
@testable import MedProbe

final class LibreLinkUpTests: XCTestCase {

    // MARK: - parsing

    func testParsesAMeasurementInTheReportedFormat() throws {
        let payload: [String: Any] = [
            "ValueInMgPerDl": 145,
            "FactoryTimestamp": "9/8/2026 6:42:11 PM",
            "TrendArrow": 3,
            "isHigh": false,
            "isLow": false
        ]

        let measurement = try LibreLinkUpAPI.parse(payload)

        XCTAssertEqual(measurement.mgdl, 145)
        XCTAssertEqual(measurement.trendArrow, 3)
        XCTAssertFalse(measurement.isHigh)
    }

    func testTimestampIsReadAsUTCRegardlessOfPhoneLocale() {
        // The service reports UTC in a US format; a phone in another locale must not
        // silently misread it.
        let date = LibreLinkUpAPI.parseTimestamp("9/8/2026 6:42:11 PM")
        XCTAssertNotNil(date)

        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 8
        components.hour = 18; components.minute = 42; components.second = 11
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertEqual(date, calendar.date(from: components))
    }

    func testMissingFieldsAreReportedRatherThanDefaulted() {
        XCTAssertThrowsError(try LibreLinkUpAPI.parse(["FactoryTimestamp": "9/8/2026 6:42:11 PM"]))
        XCTAssertThrowsError(try LibreLinkUpAPI.parse(["ValueInMgPerDl": 100]))
    }

    // MARK: - trend mapping

    func testTrendArrowsMapToTheSharedVocabulary() {
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 1), .fallingQuickly)
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 2), .falling)
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 3), .steady)
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 4), .rising)
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 5), .risingQuickly)
    }

    func testMissingOrUnknownArrowIsUnknownNotSteady() {
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: nil), .unknown)
        XCTAssertEqual(LibreLinkUpAPI.trend(fromArrow: 9), .unknown)
    }

    // MARK: - normalisation

    func testNormalisationDerivesASequenceFromTheMeasurementTime() {
        let timestamp = Date(timeIntervalSince1970: 1_757_000_000)
        let measurement = LibreGlucoseMeasurement(mgdl: 145, timestamp: timestamp,
                                                  trendArrow: 4, isHigh: false, isLow: false)

        let reading = LibreLinkUpSource.normalise(measurement)

        XCTAssertEqual(reading.source, .libreLinkUp)
        XCTAssertEqual(reading.sequence, 1_757_000_000, "the timestamp is the sequence")
        XCTAssertEqual(reading.measuredAt, timestamp)
        XCTAssertEqual(reading.trend, .rising)
        XCTAssertEqual(reading.mmoll, 8.05, accuracy: 0.01)
    }

    func testRepeatedPollsOfTheSameMeasurementAreDeduplicated() {
        // Polling is faster than the sensor produces values, so this is the normal case.
        let timestamp = Date(timeIntervalSince1970: 1_757_000_000)
        let measurement = LibreGlucoseMeasurement(mgdl: 145, timestamp: timestamp,
                                                  trendArrow: 3, isHigh: false, isLow: false)

        var policy = ReadingAcceptancePolicy()
        XCTAssertNoThrow(try policy.accept(LibreLinkUpSource.normalise(measurement)).get())

        let second = policy.accept(LibreLinkUpSource.normalise(measurement))
        if case .failure(let rejection) = second {
            XCTAssertEqual(rejection, .duplicateSequence(1_757_000_000))
        } else {
            XCTFail("the same measurement must not be published twice")
        }
    }

    // MARK: - regions

    func testEuropeIsTheDefaultRegion() {
        let credentials = LibreCredentials(store: InMemorySecretStore())
        XCTAssertEqual(credentials.region, .europe)
        XCTAssertEqual(LibreRegion.europe.host, "api-eu.libreview.io")
    }

    func testEveryRegionHasItsOwnHost() {
        let hosts = Set(LibreRegion.allCases.map(\.host))
        XCTAssertEqual(hosts.count, LibreRegion.allCases.count)
    }

    // MARK: - credential storage

    func testCredentialsRoundTripAndReportReadiness() {
        let credentials = LibreCredentials(store: InMemorySecretStore())
        XCTAssertFalse(credentials.hasLogin)

        credentials.email = "nobody@example.invalid"
        credentials.password = "not-a-real-password"

        XCTAssertTrue(credentials.hasLogin)
        XCTAssertFalse(credentials.hasSession, "a login is not a session")
    }

    func testClearingTheSessionKeepsTheLogin() {
        let credentials = LibreCredentials(store: InMemorySecretStore())
        credentials.email = "nobody@example.invalid"
        credentials.password = "not-a-real-password"
        credentials.token = "fake-token"
        credentials.accountID = "fake-account"

        XCTAssertTrue(credentials.hasSession)

        credentials.clearSession()

        // A 401 must be retryable without asking the user to type the password again.
        XCTAssertFalse(credentials.hasSession)
        XCTAssertTrue(credentials.hasLogin)
    }

    func testSignOutRemovesEverything() {
        let credentials = LibreCredentials(store: InMemorySecretStore())
        credentials.email = "nobody@example.invalid"
        credentials.password = "not-a-real-password"
        credentials.token = "fake-token"

        credentials.clearAll()

        XCTAssertFalse(credentials.hasLogin)
        XCTAssertFalse(credentials.hasSession)
        XCTAssertNil(credentials.token)
    }

    // MARK: - rate limiting

    func testRateLimitIsShorterThanThePollIntervalButNotZero() {
        // The heartbeat listener can fire far more often than the poll timer; the floor is
        // what stops it hammering the service.
        XCTAssertLessThan(LibreLinkUpSource.minimumFetchInterval, LibreLinkUpSource.defaultPollInterval)
        XCTAssertGreaterThan(LibreLinkUpSource.minimumFetchInterval, 0)
    }

    // MARK: - heartbeat listener safety

    func testHeartbeatListenerIsOffUnlessDeliberatelyEnabled() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: LibreHeartbeatListener.enabledKey)
        defer { defaults.set(previous, forKey: LibreHeartbeatListener.enabledKey) }

        defaults.removeObject(forKey: LibreHeartbeatListener.enabledKey)
        XCTAssertFalse(LibreHeartbeatListener.isEnabled, "experimental features must default to off")
    }

    func testHeartbeatListenerSubscribesToTheNotifyCharacteristicOnly() {
        // The write characteristic is named in the source only so it can be excluded;
        // it must never be the one subscribed to.
        XCTAssertEqual(LibreHeartbeatListener.notifyCharacteristicUUID.uuidString, "F002")
        XCTAssertEqual(LibreHeartbeatListener.excludedCharacteristicUUID.uuidString, "F001")
        XCTAssertNotEqual(LibreHeartbeatListener.notifyCharacteristicUUID,
                          LibreHeartbeatListener.excludedCharacteristicUUID)
        XCTAssertEqual(LibreHeartbeatListener.serviceUUID.uuidString, "FDE3")
    }
}
