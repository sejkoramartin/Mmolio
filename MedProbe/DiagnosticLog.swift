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

/// One line in the on-screen event log.
struct DiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: DiagnosticLevel
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

    func info(_ message: String) {
        append(.info, message)
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        append(.warning, message)
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        append(.error, message)
        logger.error("\(message, privacy: .public)")
    }

    private func append(_ level: DiagnosticLevel, _ message: String) {
        events.insert(DiagnosticEvent(timestamp: Date(), level: level, message: message), at: 0)
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
    }
}

/// App-wide constants that are not part of the Medtrum protocol.
enum MedProbeConstants {
    static let logSubsystem = "cz.sejkora.MedProbe"
}
