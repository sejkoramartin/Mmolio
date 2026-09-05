//
//  ContentView.swift
//  MedProbe
//
//  Single diagnostic screen. No charts, no alarms, no history — this is a probe.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {

    @ObservedObject var bluetoothManager: MedtrumBluetoothManager
    @ObservedObject private var log: DiagnosticLog

    init(bluetoothManager: MedtrumBluetoothManager) {
        self.bluetoothManager = bluetoothManager
        self.log = bluetoothManager.log
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                glucoseSection
                packetSection
                logSection
            }
            .listStyle(.plain)
            .navigationTitle("MedProbe")
        }
    }

    // MARK: - sections

    private var statusSection: some View {
        Section("Status") {
            row("Bluetooth", bluetoothManager.bluetoothState.displayName)
            row("Pump", bluetoothManager.pumpName ?? "—")
            row("State", bluetoothManager.connectionState.rawValue)
            row("Packets", "\(bluetoothManager.packetsReceived)")
        }
    }

    @ViewBuilder
    private var glucoseSection: some View {
        Section("Glucose") {
            if let reading = bluetoothManager.lastReading {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f mmol/L", reading.mmoll))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(format: "%.0f mg/dL", reading.mgdl))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)

                row("Raw glucose", "\(reading.rawGlucose)")
                row("Calibration", "\(reading.calibrationFactor)")
                row("Counter", "\(reading.counter)")
                row("Last packet", Self.timeFormatter.string(from: reading.receivedAt))
                row("History raw", reading.historyRawGlucose.map(String.init).joined(separator: ", "))
            } else {
                Text("Waiting for first CGM packet…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var packetSection: some View {
        Section("Raw packet") {
            if let reading = bluetoothManager.lastReading {
                Text(reading.rawPacketHex)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("—").foregroundStyle(.secondary)
            }

            if let rejectedHex = bluetoothManager.lastRejectedPacketHex {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last rejected packet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(rejectedHex)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    if let reason = bluetoothManager.lastRejectionReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var logSection: some View {
        Section("Log") {
            ForEach(log.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.timeFormatter.string(from: event.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(event.message)
                        .font(.caption)
                        .foregroundStyle(color(for: event.level))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func color(for level: DiagnosticLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
