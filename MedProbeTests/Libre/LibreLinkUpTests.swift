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
            XCTAssertEqual(rejection, ReadingAcceptancePolicy.Rejection.duplicateSequence(1_757_000_000))
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

// MARK: - client headers
//
// A 403 from LibreLinkUp is about the client, not the password, and these two values are
// what the service checks. They are pinned so a change is deliberate rather than accidental.

extension LibreLinkUpTests {

    func testClientIdentifiesItselfTheWayTheServiceExpects() {
        // llu.ios was rejected with 403 on a real account; every working community client
        // sends llu.android.
        XCTAssertEqual(LibreLinkUpAPI.Header.product, "llu.android")
        XCTAssertFalse(LibreLinkUpAPI.Header.version.isEmpty)
    }

    func testAccountIdIsHashedNotSentInClear() {
        let hashed = LibreLinkUpAPI.sha256Hex("some-account-id")

        XCTAssertEqual(hashed.count, 64, "SHA-256 as hex is 64 characters")
        XCTAssertFalse(hashed.contains("some-account-id"))
        // Same input, same digest — the header has to be stable across requests.
        XCTAssertEqual(hashed, LibreLinkUpAPI.sha256Hex("some-account-id"))
        XCTAssertNotEqual(hashed, LibreLinkUpAPI.sha256Hex("another-account-id"))
    }

    func testKnownDigest() {
        // Pins the implementation against a published vector, so a broken hash cannot
        // pass by being merely self-consistent.
        XCTAssertEqual(LibreLinkUpAPI.sha256Hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

// MARK: - Keychain failures are reported

extension LibreLinkUpTests {

    /// Refuses every write, standing in for a Keychain that is unavailable.
    private final class FailingSecretStore: SecretStoring {
        func set(_ value: String?, for key: String) throws {
            throw KeychainError.unexpectedStatus(errSecMissingEntitlement)
        }
        func value(for key: String) -> String? { nil }
        func removeAll() throws {}
    }

    func testAFailedKeychainWriteIsReportedRatherThanAppearingToSucceed() {
        let credentials = LibreCredentials(store: FailingSecretStore())

        let result = credentials.storeLogin(email: "nobody@example.invalid",
                                            password: "not-a-real-password",
                                            region: .europe)

        // The bug this replaces: the form went to its signed-in state while hasLogin
        // stayed false, and the source then reported no account configured.
        guard case .failure = result else {
            return XCTFail("a Keychain that stores nothing must not report success")
        }
        XCTAssertFalse(credentials.hasLogin)
    }

    func testASuccessfulWriteIsConfirmedByReadingItBack() {
        let credentials = LibreCredentials(store: InMemorySecretStore())

        let result = credentials.storeLogin(email: "nobody@example.invalid",
                                            password: "not-a-real-password",
                                            region: .germany)

        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(credentials.hasLogin)
        XCTAssertEqual(credentials.region, .germany)
        XCTAssertFalse(credentials.hasSession, "storing a login must not fabricate a session")
    }

    func testKeychainErrorsDescribeThemselvesUsefully() {
        let missing = KeychainError.unexpectedStatus(errSecMissingEntitlement)
        XCTAssertTrue(missing.diagnosticDescription.contains("entitlement"))

        let unknown = KeychainError.unexpectedStatus(-12345)
        XCTAssertTrue(unknown.diagnosticDescription.contains("-12345"))
    }
}

// MARK: - why a sign-in was refused
//
// The service has four distinct answers to a sign-in and they need four distinct
// messages. An earlier version reported all of them as a region problem, which sent the
// user looking in the wrong place.

extension LibreLinkUpTests {

    func testStatusTwoIsReportedAsWrongCredentialsNotAsARegionProblem() {
        let message = LibreLinkUpAPI.describeLoginStatus(2)

        XCTAssertTrue(message.lowercased().contains("password"))
        XCTAssertFalse(message.lowercased().contains("region"),
                       "status 2 is a credential problem; saying region sends the user the wrong way")
    }

    func testStatusTwoMentionsThatLibreLinkUpIsASeparateAccount() {
        // The most common cause: trying the Libre app's own credentials.
        XCTAssertTrue(LibreLinkUpAPI.describeLoginStatus(2).contains("separate account"))
    }

    func testRateLimitStatusSuggestsWaiting() {
        XCTAssertTrue(LibreLinkUpAPI.describeLoginStatus(429).lowercased().contains("wait"))
    }

    func testUnknownStatusStillReportsItsNumber() {
        XCTAssertTrue(LibreLinkUpAPI.describeLoginStatus(77).contains("77"))
    }
}

// MARK: - region discovery
//
// The service knows where an account lives and says so with a redirect. Following it is
// more reliable than asking the user to pick, because a wrong pick fails as an
// authentication error with nothing pointing at the region.

extension LibreLinkUpTests {

    func testSignInStartsAtTheRegionAgnosticHost() {
        // Starting at a regional host means a wrong stored region fails before the
        // service ever gets the chance to correct it.
        XCTAssertEqual(LibreLinkUpAPI.globalHost, "api.libreview.io")
        XCTAssertFalse(LibreLinkUpAPI.globalHost.contains("-"),
                       "the entry point must not be a regional host")
    }

    func testSessionDefaultsToTheGlobalHostUntilOneIsDiscovered() {
        let session = LibreSession(token: "fake", accountID: "fake", patientID: nil)
        XCTAssertEqual(session.host, LibreLinkUpAPI.globalHost)
    }

    func testSessionCarriesTheDiscoveredHost() {
        let session = LibreSession(token: "fake", accountID: "fake",
                                   patientID: nil, host: "api-de.libreview.io")
        XCTAssertEqual(session.host, "api-de.libreview.io")
    }

    func testDiscoveredHostSurvivesASessionBeingCleared() {
        let credentials = LibreCredentials(store: InMemorySecretStore())
        credentials.token = "fake-token"
        credentials.accountID = "fake-account"
        credentials.host = "api-de.libreview.io"

        credentials.clearSession()

        // The token expires; where the account lives does not.
        XCTAssertNil(credentials.token)
        XCTAssertEqual(credentials.host, "api-de.libreview.io")
    }

    func testClientSendsTheHeadersTheServiceChecks() {
        // Verified against a client known to work against this account today.
        XCTAssertEqual(LibreLinkUpAPI.Header.product, "llu.android")
        XCTAssertEqual(LibreLinkUpAPI.Header.version, "4.16.0")
        XCTAssertTrue(LibreLinkUpAPI.Header.userAgent.contains("LibreLinkUp"),
                      "URLSession's default user agent is not accepted")
        XCTAssertTrue(LibreLinkUpAPI.Header.userAgent.contains(LibreLinkUpAPI.Header.version),
                      "the user agent should carry the same version as the header")
    }
}
