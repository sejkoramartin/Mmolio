//
//  CGMStreamTracker.swift
//  MedProbe
//
//  Tracks the health of the 669A9141 glucose stream and decides what a newly arrived
//  reading actually contributes: is it a duplicate, and does it reveal a gap that the
//  packet's own history slots can fill?
//
//  Two behaviours, both taken from upstream xDrip4iOS:
//
//  1. Inactivity watchdog. A healthy sensor notifies every two minutes. Upstream allows
//     seven minutes — about three missed cycles — before treating an apparently connected
//     session as stale and recycling it.
//
//  2. Backfill. Each packet carries the three previous cycles as a shift register, so a
//     short outage can be filled in after recovery, capped at those three slots.
//
//  Pure value type. No CoreBluetooth, no clock of its own — the caller passes the time in,
//  which is what makes the watchdog testable without waiting seven minutes.
//

import Foundation

/// A reading recovered from a packet's history slots rather than received live.
struct BackfilledReading: Equatable {

    /// Reading counter this value belongs to.
    let counter: Int

    /// Raw sensor value from the history slot.
    let rawGlucose: UInt16

    let mgdl: Double

    /// Reconstructed time: the live packet's timestamp, less one cycle per slot.
    let timestamp: Date

    var mmoll: Double {
        mgdl / MedtrumReading.mgdlPerMmoll
    }
}

/// What a newly decoded reading contributed.
struct StreamUpdate: Equatable {

    /// True when this counter had already been delivered and the reading was ignored.
    let isDuplicate: Bool

    /// Cycles missed between the last delivered reading and this one, as implied by the counter.
    let missedCycles: Int

    /// Readings recovered from the packet's history slots, oldest first.
    let backfilled: [BackfilledReading]
}

/// Keeps just enough state to spot duplicates, gaps and a stalled stream.
struct CGMStreamTracker: Equatable {

    /// One CGM cycle. The counter advances by one per cycle.
    static let cycleDuration: TimeInterval = 2 * 60

    /// Upstream's `packetInactivityTimeout`: three missed cycles plus a margin.
    static let inactivityTimeout: TimeInterval = 7 * 60

    /// A packet carries the current reading plus three history slots.
    static let historySlotCount = 3

    /// When the last packet that decoded cleanly arrived.
    private(set) var lastValidPacketAt: Date?

    /// Counter of the most recently delivered reading, if any.
    private(set) var lastDeliveredCounter: Int?

    /// Total readings delivered live this session.
    private(set) var deliveredCount: Int = 0

    /// Total readings recovered from history slots this session.
    private(set) var backfilledCount: Int = 0

    /// Cycles the counter says we never saw, live or backfilled.
    private(set) var missedCycleCount: Int = 0

    // MARK: - watchdog

    /// True when the stream has been silent long enough to suspect the session, rather
    /// than merely being between cycles.
    ///
    /// Before the first packet the watchdog measures from `since`, which the caller sets
    /// when it subscribes — otherwise a session that never delivers anything would never
    /// look stale.
    func isStale(now: Date, since: Date) -> Bool {
        let reference = lastValidPacketAt ?? since
        return now.timeIntervalSince(reference) >= Self.inactivityTimeout
    }

    /// Age of the last valid packet, for display.
    func packetAge(now: Date) -> TimeInterval? {
        lastValidPacketAt.map { now.timeIntervalSince($0) }
    }

    // MARK: - accepting readings

    /// Records a decoded reading and reports what it contributed.
    ///
    /// Duplicates are expected: CoreBluetooth state restoration can replay a packet, and
    /// the pump may repeat one. They update the watchdog — the link is clearly alive — but
    /// deliver nothing.
    mutating func accept(_ reading: MedtrumReading) -> StreamUpdate {

        lastValidPacketAt = reading.receivedAt

        guard let previous = lastDeliveredCounter else {
            // First reading of the session: nothing to compare against, nothing to fill.
            lastDeliveredCounter = reading.counter
            deliveredCount += 1
            return StreamUpdate(isDuplicate: false, missedCycles: 0, backfilled: [])
        }

        if reading.counter == previous {
            return StreamUpdate(isDuplicate: true, missedCycles: 0, backfilled: [])
        }

        // A counter that went backwards means a new sensor session, or a replayed packet
        // from before a restart. Start over rather than inventing a huge gap.
        guard reading.counter > previous else {
            lastDeliveredCounter = reading.counter
            deliveredCount += 1
            return StreamUpdate(isDuplicate: false, missedCycles: 0, backfilled: [])
        }

        let gap = reading.counter - previous - 1
        let recovered = gap > 0 ? backfill(from: reading, gap: gap) : []

        lastDeliveredCounter = reading.counter
        deliveredCount += 1
        backfilledCount += recovered.count
        missedCycleCount += max(0, gap - recovered.count)

        return StreamUpdate(isDuplicate: false, missedCycles: gap, backfilled: recovered)
    }

    /// Rebuilds missing readings from the packet's history slots.
    ///
    /// Slot 0 is one cycle back, slot 1 two cycles, slot 2 three. Only slots that fall
    /// inside the gap are used, and each is plausibility-checked exactly like a live
    /// reading — a recovered value must never bypass the gate a live one has to pass.
    private func backfill(from reading: MedtrumReading, gap: Int) -> [BackfilledReading] {
        let usable = min(Self.historySlotCount, gap)
        guard usable > 0, reading.calibrationFactor > 0 else { return [] }

        var recovered: [BackfilledReading] = []

        for slot in 1...usable {
            let raw = reading.historyRawGlucose[slot - 1]
            let mgdl = Double(raw) * 1000.0 / Double(reading.calibrationFactor)

            guard mgdl >= MedtrumPacketDecoder.minPlausibleMgdl,
                  mgdl <= MedtrumPacketDecoder.maxPlausibleMgdl else { continue }

            recovered.append(
                BackfilledReading(
                    counter: reading.counter - slot,
                    rawGlucose: raw,
                    mgdl: mgdl,
                    timestamp: reading.receivedAt.addingTimeInterval(-Double(slot) * Self.cycleDuration)
                )
            )
        }

        // Oldest first, so callers can append them in chronological order.
        return recovered.reversed()
    }

    /// Forgets stream position without clearing counts. Used when a new sensor session is
    /// detected, so the next reading is treated as a fresh start rather than a huge gap.
    mutating func resetStreamPosition() {
        lastDeliveredCounter = nil
    }
}
