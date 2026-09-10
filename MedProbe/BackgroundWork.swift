//
//  BackgroundWork.swift
//  MedProbe
//
//  Asking iOS for enough time to finish a piece of work.
//
//  A suspended app gets a few seconds when something wakes it — a BLE notification, for
//  instance. Fetching a reading over HTTP and then sending it to the watch does not
//  reliably fit in that, and work cut off halfway is worse than work not started: the
//  reading is fetched, the watch never hears about it, and the send policy has already
//  recorded it as delivered.
//
//  beginBackgroundTask asks for a longer window. It is not a promise — iOS can still end
//  it — but it turns "a few seconds" into "up to about thirty".
//

import Foundation
import UIKit

/// Keeps the app awake for one piece of work.
///
/// Balanced by construction: the task ends when the guard is released, including on the
/// expiration path, so a forgotten `end` cannot leak an assertion and get the app killed.
final class BackgroundWork {

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let name: String
    private let log: DiagnosticLog?

    init(_ name: String, log: DiagnosticLog? = nil) {
        self.name = name
        self.log = log
    }

    /// Requests extra time. Safe to call when already running; the second call does nothing.
    func begin() {
        guard identifier == .invalid else { return }

        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // iOS is out of patience. Ending here is mandatory: an assertion left
            // outstanding at expiry terminates the app.
            self?.log?.warning("Background time expired during \(self?.name ?? "work")", .diagnostic)
            self?.end()
        }
    }

    /// Gives the time back. Idempotent.
    func end() {
        guard identifier != .invalid else { return }
        let finished = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(finished)
    }

    deinit {
        end()
    }

    /// Runs async work with extra time, ending the task however the work finishes.
    static func run(_ name: String,
                    log: DiagnosticLog? = nil,
                    work: @escaping () async -> Void) {
        let guardian = BackgroundWork(name, log: log)
        guardian.begin()

        Task {
            await work()
            await MainActor.run { guardian.end() }
        }
    }
}
