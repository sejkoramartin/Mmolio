//
//  ListeningMode.swift
//  MedProbe
//
//  Which characteristics MedProbe subscribes to.
//
//  Three modes exist so the "does subscribing to more than one characteristic break the
//  glucose stream?" question can be answered by experiment rather than argument. All three
//  are read-only: they differ only in how many notifications are enabled.
//

import Foundation

enum ListeningMode: String, CaseIterable, Identifiable {

    /// 669A9141 only — as close as MedProbe gets to the upstream xDrip4iOS Medtrum
    /// transmitter, which subscribes to its receive characteristic and nothing else.
    ///
    /// Deliberately blind: without 669A9120 there is no CGM state byte, so a silent
    /// stream cannot be distinguished from a pump that is simply not transmitting. That
    /// is the price of parity, and the reason this mode is for experiments, not for use.
    case xdripParity

    /// 669A9141 plus 669A9120. The status stream carries the CGM state byte, which is the
    /// only signal that says whether silence is expected.
    case production

    /// Everything that advertises notify or indicate, including 669A9101. This is how the
    /// protocol was mapped, and the only mode that sees the fragmented reply stream.
    case diagnostic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xdripParity: return "xDrip parity (9141 only)"
        case .production: return "Production (9141 + 9120)"
        case .diagnostic: return "Diagnostic (everything)"
        }
    }

    var explanation: String {
        switch self {
        case .xdripParity:
            return "Matches upstream xDrip. No CGM state byte, so silence is unexplainable."
        case .production:
            return "Adds the status stream, which says whether the pump is transmitting."
        case .diagnostic:
            return "Adds the fragmented reply stream. Highest BLE footprint."
        }
    }

    /// Characteristic UUID strings this mode subscribes to.
    /// Nil means "every characteristic that advertises notify or indicate".
    func subscribedCharacteristics(cgm: String, status: String) -> Set<String>? {
        switch self {
        case .xdripParity: return [cgm]
        case .production: return [cgm, status]
        case .diagnostic: return nil
        }
    }

    // MARK: - persistence

    static let storageKey = "medprobe.listeningMode"

    static var current: ListeningMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let mode = ListeningMode(rawValue: raw) else { return .production }
        return mode
    }
}
