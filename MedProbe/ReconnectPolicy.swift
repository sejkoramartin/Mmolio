//
//  ReconnectPolicy.swift
//  MedProbe
//
//  Bounded backoff for reconnect attempts.
//
//  Delays mirror the upstream xDrip4iOS Medtrum transmitter
//  (JohanDegraeve/xdripswift, CGMMedtrumTouchCareNanoTransmitter.swift), whose comment
//  explains why they exist: "EasyPatch owns the physical session. Back off repeated
//  retries so a rejected passive listener cannot enter the rapid, battery-intensive
//  connect/disconnect loops seen in logs."
//
//  Pure value type, no CoreBluetooth, so the state machine is unit-testable.
//

import Foundation

/// Why a reconnect was scheduled. Surfaced in diagnostics so a reconnect loop is legible
/// rather than mysterious.
enum ReconnectReason: String, Equatable {

    /// The peripheral disconnected on its own, or the link dropped.
    case disconnected = "disconnected"

    /// A connect attempt failed outright.
    case connectFailed = "connect failed"

    /// No valid CGM packet for longer than the watchdog allows, while apparently connected.
    case cgmStreamStalled = "CGM stream stalled"

    /// The connection sat in .connecting without making progress.
    case connectionStalled = "connection stalled"
}

/// Decides how long to wait before the next reconnect attempt.
struct ReconnectPolicy: Equatable {

    /// Same ladder as upstream: 5s, 10s, then 15s for every attempt after that.
    static let delays: [TimeInterval] = [5, 10, 15]

    /// Attempts made since the last success. Zero when the link is healthy.
    private(set) var attempt: Int = 0

    /// Returns the delay for the next attempt and advances the ladder.
    mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    /// Delay the next attempt would use, without advancing. For display only.
    var upcomingDelay: TimeInterval {
        Self.delays[min(attempt, Self.delays.count - 1)]
    }

    /// Called once the link is genuinely working again — meaning a valid packet arrived,
    /// not merely that CoreBluetooth reported a connection. A connection that connects and
    /// then delivers nothing is the failure we are recovering from, so it must not reset
    /// the ladder.
    mutating func reset() {
        attempt = 0
    }
}
