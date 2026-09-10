//
//  DiagnosticLog.swift
//  MedProbe
//
//  Small in-memory ring of recent events, mirrored to OSLog.
//

import Foundation
import OSLog

/// Severity of a diagnostic event. Only affects presentation.
enum DiagnosticLevel: String {
    case info
    case warning
    case error
}

/// Which part of the system an event came from, so a lifecycle question can be answered
/// from the log without guessing which line belongs to what.
enum DiagnosticCategory: String {

    /// CoreBluetooth lifecycle: connect, discovery, subscription, restoration.
    case ble = "BLE"

    /// Glucose readings and the CGM stream's health.
    case cgm = "CGM"

    /// The capture file and the Clear button.
    case recorder = "REC"

    /// Anything else worth recording about the app itself.
    case diagnostic = "DIAG"
}

/// One line in the on-screen event log.
struct DiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: DiagnosticLevel
    let category: DiagnosticCategory
    let message: String
}

/// Keeps the last `capacity` events for the diagnostic screen and forwards everything to OSLog.
///
/// Nothing therapy-related is ever passed in here, because MedProbe never receives
/// therapy data in the first place.
///
/// Not thread-safe by design: every caller runs on the main queue, because the
/// `CBCentralManager` is created with `queue: nil` and therefore delivers all of its
/// delegate callbacks there. That also keeps `@Published` mutation on the main thread.
final class DiagnosticLog: ObservableObject {

    /// Newest first, so the UI can render straight down the list.
    @Published private(set) var events: [DiagnosticEvent] = []

    private let capacity: Int
    private let logger: Logger

    init(category: String, capacity: Int = 200) {
        self.capacity = capacity
        self.logger = Logger(subsystem: MedProbeConstants.logSubsystem, category: category)
    }

    func info(_ message: String, _ category: DiagnosticCategory = .diagnostic) {
        append(.info, category, message)
        logger.info("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
    }

    func warning(_ message: String, _ category: DiagnosticCategory = .diagnostic) {
        append(.warning, category, message)
        logger.warning("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
    }

    func error(_ message: String, _ category: DiagnosticCategory = .diagnostic) {
        append(.error, category, message)
        logger.error("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
    }

    private func append(_ level: DiagnosticLevel, _ category: DiagnosticCategory, _ message: String) {
        events.insert(
            DiagnosticEvent(timestamp: Date(), level: level, category: category, message: message),
            at: 0
        )
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
    }
}

/// App-wide constants that are not part of the Medtrum protocol.
enum MedProbeConstants {

    static let logSubsystem = "cz.sejkora.MedProbe"

    /// UserDefaults key behind the diagnostic-mode switch.
    ///
    /// MedProbe is a CGM reader. Insulin delivery and alarm values are parsed — the field
    /// widths are needed to find the CGM field, and the bolus/reservoir cross-check is how
    /// we know the offsets are right — but they stay off screen and out of the event log
    /// unless this is deliberately switched on.
    static let diagnosticModeKey = "diagnosticMode"

    /// Whether the diagnostics tab is shown. Off by default: it is a tool for finding
    /// problems, not something to meet on opening the app.
    static let showDiagnosticsKey = "medprobe.showDiagnostics"

    /// Whether therapy values may currently be displayed and logged. Off by default.
    static var isDiagnosticModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: diagnosticModeKey)
    }
}
