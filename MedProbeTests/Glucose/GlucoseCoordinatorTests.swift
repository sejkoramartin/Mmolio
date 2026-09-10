//
//  GlucoseCoordinatorTests.swift
//  MedProbeTests
//
//  Source selection and forwarding to the watch, using stand-in sources so no radio or
//  network is involved.
//

import XCTest
import Combine
@testable import MedProbe

/// Records what it was asked to send, and can be told to fail.
private final class RecordingTransport: GarminTransport {

    private(set) var devices: [GarminDevice] = []
    private(set) var selectedDevice: GarminDevice?
    private(set) var lastSentAt: Date?
    private(set) var lastError: GarminTransportError?

    private(set) var sent: [GlucoseReading] = []
    var failWith: GarminTransportError?

    var devicesPublisher: AnyPublisher<[GarminDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }
    private let devicesSubject = CurrentValueSubject<[GarminDevice], Never>([])

    private var policy = GarminSendPolicy()

    func select(_ device: GarminDevice?) { selectedDevice = device }
    func start() {}
    func stop() {}
    func requestDevices() {}
    func handleReturn(from url: URL) {}

    func announce(_ found: [GarminDevice]) {
        devices = found
        devicesSubject.send(found)
    }

    func send(_ reading: GlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        guard policy.decide(reading) == .send else {
            completion(.success(()))
            return
        }
        if let failWith {
            lastError = failWith
            completion(.failure(failWith))
            return
        }
        sent.append(reading)
        lastSentAt = Date()
        completion(.success(()))
    }
}

final class GlucoseCoordinatorTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)

    private func reading(_ mgdl: Double, source: GlucoseSourceKind, sequence: Int,
                         at offset: TimeInterval = 0) -> GlucoseReading {
        GlucoseReading(mgdl: mgdl,
                       measuredAt: epoch.addingTimeInterval(offset),
                       trend: .steady,
                       source: source,
                       sequence: sequence)
    }

    // MARK: - send policy through a transport

    func testEachDistinctReadingIsSentOnce() {
        let transport = RecordingTransport()

        transport.send(reading(100, source: .medtrum, sequence: 1)) { _ in }
        transport.send(reading(105, source: .medtrum, sequence: 2, at: 120)) { _ in }

        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(transport.sent.map(\.sequence), [1, 2])
    }

    func testARepeatedReadingIsNotSentAgain() {
        let transport = RecordingTransport()

        transport.send(reading(100, source: .medtrum, sequence: 1)) { _ in }
        transport.send(reading(100, source: .medtrum, sequence: 1, at: 120)) { _ in }

        XCTAssertEqual(transport.sent.count, 1, "the watch must not be woken for a reading it has")
    }

    func testAnOlderReadingIsNotSent() {
        let transport = RecordingTransport()

        transport.send(reading(100, source: .medtrum, sequence: 10)) { _ in }
        transport.send(reading(95, source: .medtrum, sequence: 9, at: 120)) { _ in }

        XCTAssertEqual(transport.sent.map(\.sequence), [10])
    }

    func testSwitchingSourceDoesNotDiscardTheFirstReadingFromTheNewOne() {
        let transport = RecordingTransport()

        // A Medtrum counter in the thousands followed by a Libre sequence that looks
        // small: without the source check the Libre reading would be treated as stale.
        transport.send(reading(100, source: .medtrum, sequence: 5469)) { _ in }
        transport.send(reading(120, source: .libreLinkUp, sequence: 3, at: 120)) { _ in }

        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertEqual(transport.sent.last?.source, .libreLinkUp)
    }

    // MARK: - failure reporting

    func testASendFailureIsReportedRatherThanSwallowed() {
        let transport = RecordingTransport()
        transport.failWith = .deviceNotConnected

        var received: GarminTransportError?
        transport.send(reading(100, source: .medtrum, sequence: 1)) { result in
            if case .failure(let error) = result { received = error }
        }

        XCTAssertEqual(received, .deviceNotConnected)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: - device selection

    func testDeviceSelectionIsRemembered() {
        let transport = RecordingTransport()
        let watch = GarminDevice(id: 42, name: "Forerunner 165", isConnected: true)

        transport.announce([watch])
        transport.select(watch)

        XCTAssertEqual(transport.selectedDevice?.id, 42)
        XCTAssertEqual(transport.devices.count, 1)
    }

    func testSourceSelectionDefaultsToMedtrumAndSurvivesABadStoredValue() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: SelectedSource.storageKey)
        defer { defaults.set(previous, forKey: SelectedSource.storageKey) }

        defaults.removeObject(forKey: SelectedSource.storageKey)
        XCTAssertEqual(SelectedSource.current, .medtrum)

        defaults.set("nonsense", forKey: SelectedSource.storageKey)
        XCTAssertEqual(SelectedSource.current, .medtrum, "a bad value must not leave the app without a source")

        defaults.set(SelectedSource.libreLinkUp.rawValue, forKey: SelectedSource.storageKey)
        XCTAssertEqual(SelectedSource.current, .libreLinkUp)
    }

    func testSelectedSourceMapsToItsKind() {
        XCTAssertEqual(SelectedSource.medtrum.kind, .medtrum)
        XCTAssertEqual(SelectedSource.libreLinkUp.kind, .libreLinkUp)
    }
}

// MARK: - which sources the interface offers
//
// Medtrum works and its code is untouched, but its pump transmits in short windows —
// about two readings an hour — so offering it beside one that updates every minute would
// be presenting a choice that is not really a choice. It is filtered out of the picker.

extension GlucoseCoordinatorTests {

    func testOnlyLibreIsOfferedForNow() {
        XCTAssertEqual(SelectedSource.selectable, [.libreLinkUp])
        XCTAssertFalse(SelectedSource.hasChoice, "one option is not a choice worth showing")
    }

    func testMedtrumRemainsFullySupportedEvenWhileHidden() {
        // Hidden from the picker, not removed: the case, its kind and its wire value all
        // still work, so a stored reading or an old message still makes sense.
        XCTAssertTrue(SelectedSource.allCases.contains(.medtrum))
        XCTAssertEqual(SelectedSource.medtrum.kind, .medtrum)
        XCTAssertEqual(GlucoseSourceKind.medtrum.wireValue, 1)
    }

    func testTheDefaultIsSomethingTheUserCanSee() {
        XCTAssertTrue(SelectedSource.selectable.contains(SelectedSource.defaultSource))
    }

    func testAStoredSourceThatIsNoLongerOfferedFallsBack() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: SelectedSource.storageKey)
        defer { defaults.set(previous, forKey: SelectedSource.storageKey) }

        // Someone who selected Medtrum in an earlier build must not be left on a source
        // the interface no longer shows and they cannot change.
        defaults.set(SelectedSource.medtrum.rawValue, forKey: SelectedSource.storageKey)

        XCTAssertEqual(SelectedSource.current, SelectedSource.defaultSource)
        XCTAssertTrue(SelectedSource.selectable.contains(SelectedSource.current))
    }
}
