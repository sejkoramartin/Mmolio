//
//  GlucoseView.swift
//  MedProbe
//
//  The screen someone actually looks at: the current value, how it is moving, and how
//  old it is.
//
//  Everything here answers one of three questions — what is it, where is it going, can I
//  trust it. Anything that answers a fourth belongs on the diagnostics screen.
//

import SwiftUI

struct GlucoseView: View {

    @ObservedObject var coordinator: GlucoseCoordinator

    /// A reading older than this is shown as out of date rather than as current.
    /// Both sources produce a value every one to two minutes.
    private static let staleAfter: TimeInterval = 15 * 60

    /// Redraws the age without waiting for a new reading.
    @State private var now = Date()
    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            reading
            Spacer()
            footer
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onReceive(tick) { now = $0 }
    }

    // MARK: - the value

    @ViewBuilder
    private var reading: some View {
        if let reading = coordinator.latestReading {
            let isStale = reading.isStale(at: now, threshold: Self.staleAfter)

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%.1f", reading.mmoll))
                        .font(.system(size: 84, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        // Dimmed rather than hidden: an old value is still worth seeing,
                        // it just must not look current.
                        .foregroundStyle(isStale ? .secondary : .primary)

                    Text(reading.trend.arrow)
                        .font(.system(size: 44, weight: .medium))
                        // A trend from an old value says less than nothing.
                        .foregroundStyle(isStale ? .clear : .primary)
                }

                Text("mmol/L")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                age(for: reading, isStale: isStale)
            }
        } else {
            VStack(spacing: 12) {
                Text("—")
                    .font(.system(size: 84, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(waitingMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func age(for reading: GlucoseReading, isStale: Bool) -> some View {
        let minutes = Int(reading.age(at: now) / 60)

        return HStack(spacing: 6) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(minutes < 1 ? "just now" : "\(minutes) min ago")
                .foregroundStyle(isStale ? .orange : .secondary)
        }
        .font(.callout)
    }

    private var waitingMessage: String {
        switch coordinator.sourceState {
        case .connected, .connecting: return "Waiting for the first reading"
        case .disabled: return "No glucose source is switched on"
        case .idle: return "Not connected"
        case .failed(let error): return error.userFacingDescription
        }
    }

    // MARK: - status line

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColour)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }

            if let sentAt = coordinator.lastSentAt {
                Text("Watch updated \(Self.time.string(from: sentAt))")
                    .foregroundStyle(.secondary)
            } else if coordinator.selectedWatch == nil {
                Text("No watch selected")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        switch coordinator.sourceState {
        case .connected: return coordinator.selected.displayName
        case .connecting: return "Connecting…"
        case .disabled: return "Off"
        case .idle: return "Idle"
        case .failed(let error): return error.userFacingDescription
        }
    }

    private var statusColour: Color {
        switch coordinator.sourceState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .orange
        default: return .secondary
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
