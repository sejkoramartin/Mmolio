//
//  ListeningModeTests.swift
//  MedProbeTests
//

import XCTest
@testable import MedProbe

final class ListeningModeTests: XCTestCase {

    private let cgm = "669A9141-0008-968F-E311-6050405558B3"
    private let status = "669A9120-0008-968F-E311-6050405558B3"
    private let fragments = "669A9101-0008-968F-E311-6050405558B3"

    func testParityModeSubscribesToTheGlucoseCharacteristicAlone() {
        let allowed = ListeningMode.xdripParity.subscribedCharacteristics(cgm: cgm, status: status)

        XCTAssertEqual(allowed, [cgm])
        XCTAssertFalse(allowed?.contains(status) ?? true)
        XCTAssertFalse(allowed?.contains(fragments) ?? true)
    }

    func testProductionModeAddsTheStatusStream() {
        let allowed = ListeningMode.production.subscribedCharacteristics(cgm: cgm, status: status)

        XCTAssertEqual(allowed, [cgm, status])
        XCTAssertFalse(allowed?.contains(fragments) ?? true)
    }

    func testDiagnosticModeSubscribesToEverything() {
        // nil means "no filter": every notify/indicate characteristic is subscribed.
        XCTAssertNil(ListeningMode.diagnostic.subscribedCharacteristics(cgm: cgm, status: status))
    }

    func testProductionIsTheDefaultForAnUnsetOrBrokenValue() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: ListeningMode.storageKey)
        defer { defaults.set(previous, forKey: ListeningMode.storageKey) }

        defaults.removeObject(forKey: ListeningMode.storageKey)
        XCTAssertEqual(ListeningMode.current, .production)

        defaults.set("nonsense", forKey: ListeningMode.storageKey)
        XCTAssertEqual(ListeningMode.current, .production, "an unknown value must not disable listening")
    }

    func testStoredModeIsHonoured() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: ListeningMode.storageKey)
        defer { defaults.set(previous, forKey: ListeningMode.storageKey) }

        defaults.set(ListeningMode.xdripParity.rawValue, forKey: ListeningMode.storageKey)
        XCTAssertEqual(ListeningMode.current, .xdripParity)
    }

    func testEveryModeIsSelectableAndDescribed() {
        XCTAssertEqual(ListeningMode.allCases.count, 3)
        for mode in ListeningMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.explanation.isEmpty)
        }
    }
}
