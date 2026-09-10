//
//  ContentView.swift
//  MedProbe
//
//  Single diagnostic screen. No charts, no alarms, no history — this is a probe.
//

import SwiftUI
import CoreBluetooth
import UIKit

struct ContentView: View {

    @ObservedObject var bluetoothManager: MedtrumBluetoothManager
    @ObservedObject private var log: DiagnosticLog
    @ObservedObject private var recorder: PacketRecorder

    /// Off by default: therapy values stay hidden unless deliberately requested.
    @AppStorage(MedProbeConstants.diagnosticModeKey) private var diagnosticMode = false

    /// Which characteristics to subscribe to. Stored as a raw string so @AppStorage can
    /// hold it without the enum needing to be RawRepresentable for AppStorage specifically.

    @State private var isAskingForReading = false
    @State private var readingInput = ""
    @State private var exportFile: ExportFile?
    @State private var actionError: String?
    @State private var isConfirmingClear = false

    init(bluetoothManager: MedtrumBluetoothManager) {
        self.bluetoothManager = bluetoothManager
        self.log = bluetoothManager.log
        self.recorder = bluetoothManager.recorder
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                streamHealthSection
                protocolSection
                captureSection
                characteristicsSection
                glucoseSection
                packetSection
                logSection
            }
            .listStyle(.plain)
            .navigationTitle("MedProbe")
            .alert("EasyPatch reading", isPresented: $isAskingForReading) {
                TextField("mmol/L, e.g. 10.6", text: $readingInput)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { readingInput = "" }
                Button("Mark") { markReading() }
            } message: {
                Text("Stored with the exact time you tap Mark, alongside the packets. Never used for decoding.")
            }
            .alert("Delete captured records?", isPresented: $isConfirmingClear) {
                Button("Cancel", role: .cancel) { }
                Button("Delete records", role: .destructive) { recorder.clear() }
            } message: {
                // The earlier wording was "Delete and restart", which read as though it
                // restarted the connection. It never did: this button only touches the
                // capture file.
                Text("Deletes the \(recorder.recordCount) records captured so far and starts a new capture file. Does not affect the Bluetooth connection.")
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url)
            }
        }
    }

    // MARK: - stream health

    /// Everything needed to judge whether the CGM stream is actually working, without
    /// exporting a capture to find out.
    private var streamHealthSection: some View {
        Section("CGM stream (669A9141)") {
            HStack {
                Text("Notifying")
                Spacer()
                Text(bluetoothManager.isCGMCharacteristicNotifying ? "yes" : "no")
                    .foregroundStyle(bluetoothManager.isCGMCharacteristicNotifying ? .green : .orange)
            }

            if let last = bluetoothManager.lastValidCGMPacketAt {
                let age = Int(Date().timeIntervalSince(last) / 60)
                HStack {
                    Text("Last packet")
                    Spacer()
                    Text("\(Self.timeFormatter.string(from: last))  (\(age) min)")
                        .foregroundStyle(age >= 7 ? .red : age >= 4 ? .orange : .secondary)
                        .monospacedDigit()
                }
            } else {
                row("Last packet", "never")
            }

            row("Readings", "\(bluetoothManager.cgmReadingCount)")

            if bluetoothManager.backfilledReadingCount > 0 {
                row("Backfilled", "\(bluetoothManager.backfilledReadingCount)")
            }
            if bluetoothManager.missedCycleCount > 0 {
                row("Missed cycles", "\(bluetoothManager.missedCycleCount)")
            }

            row("Reconnects", "\(bluetoothManager.reconnectCount)")

            if let reason = bluetoothManager.lastReconnectReason {
                let when = bluetoothManager.lastReconnectAt
                    .map { Self.timeFormatter.string(from: $0) } ?? "—"
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last reconnect")
                        .font(.caption)
                    Text("\(reason.rawValue) at \(when)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !bluetoothManager.lastBackfilled.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovered from history")
                        .font(.caption.weight(.semibold))
                    ForEach(bluetoothManager.lastBackfilled, id: \.counter) { reading in
                        Text(String(format: "%.1f mmol/L  counter %d  %@",
                                    reading.mmoll, reading.counter,
                                    Self.timeFormatter.string(from: reading.timestamp)))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - protocol

    /// What the AndroidAPS-derived parsers make of the live traffic.
    @ViewBuilder
    private var protocolSection: some View {
        Section("Protocol (669A9120)") {
            if let notification = bluetoothManager.lastNotification {
                row("State", String(format: "0x%02X", notification.stateRaw))
                row("Field mask", String(format: "0x%04X", notification.fieldMask))

                // The CGM field is the point of the exercise, so it leads.
                if let cgm = notification.cgmFieldBytes {
                    let hex = cgm.map { String(format: "%02X", $0) }.joined(separator: " ")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CGM field — meaning unknown")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(hex)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text("AndroidAPS reserves these 5 bytes and does not decode them.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                let visibleFields = diagnosticMode ? notification.fields : notification.nonTherapyFields
                let withheld = notification.withheldTherapyFieldCount

                if !diagnosticMode && withheld > 0 {
                    Text("\(withheld) therapy field(s) parsed and hidden")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(visibleFields, id: \.mask) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(field.name)
                                .font(.caption)
                            Spacer()
                            Text(field.interpretation ?? "not decoded")
                                .font(.caption)
                                .foregroundStyle(field.interpretation == nil ? .orange : .secondary)
                        }
                        Text(field.hex)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }

            } else {
                Text("No 669A9120 notification parsed yet")
                    .foregroundStyle(.secondary)
            }
        }

        Section("Reassembly (669A9101)") {
            row("Messages", "\(bluetoothManager.assembledFrameCount)")

            if let frame = bluetoothManager.lastAssembledFrame {
                row("Fragments", "\(frame.fragmentCount)")
                row("Declared length", "\(frame.declaredLength)")
                row("Checksums", frame.isIntact ? "valid" : "invalid")
                Text(frame.hex)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(6)
                Text("Reassembled only. Contents deliberately not interpreted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No complete message yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - capture

    /// TEMPORARY DIAGNOSTIC: capture controls for the offline correlation exercise.
    private var captureSection: some View {
        Section("Capture") {
            row("Records", "\(recorder.recordCount)")

            if let error = recorder.storageError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                readingInput = ""
                isAskingForReading = true
            } label: {
                Label("Mark EasyPatch Reading", systemImage: "drop.fill")
            }

            Button {
                export()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(recorder.recordCount == 0)

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Delete captured records", systemImage: "trash")
            }
            .disabled(recorder.recordCount == 0)

            if let latest = recorder.recentRecords.first(where: { $0.kind == .groundTruth }) {
                row("Last marked", "\(latest.hex) mmol/L at \(Self.timeFormatter.string(from: latest.timestamp))")
            }
        }
    }

    private func markReading() {
        // Accept both decimal separators; the keypad offers whichever the locale uses.
        let normalised = readingInput.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalised), value > 0 else {
            actionError = "Could not read '\(readingInput)' as a number"
            readingInput = ""
            return
        }

        recorder.recordGroundTruth(mmoll: value)
        log.info("EasyPatch reading marked: \(String(format: "%.1f", value)) mmol/L")
        readingInput = ""
        actionError = nil
    }

    private func export() {
        do {
            exportFile = ExportFile(url: try recorder.exportCSV())
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - sections

    private var statusSection: some View {
        Section("Status") {
            row("Bluetooth", bluetoothManager.bluetoothState.displayName)
            row("Pump", bluetoothManager.pumpName ?? "—")
            row("State", bluetoothManager.connectionState.rawValue)
            row("Packets", "\(bluetoothManager.packetsReceived)")

            if let state = bluetoothManager.cgmStateByte {
                let changed = bluetoothManager.cgmStateChangedAt
                    .map { Self.timeFormatter.string(from: $0) } ?? "—"
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("CGM state byte")
                        Spacer()
                        Text(String(format: "0x%02X", state))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(state == 0x03 ? .green : .orange)
                    }
                    Text(state == 0x03
                         ? "Packets on 669A9141 have only ever been seen while this is 0x03."
                         : "669A9141 has stayed silent whenever this was not 0x03. Changed at \(changed).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let units = bluetoothManager.reservoirUnits {
                let age = bluetoothManager.reservoirUpdatedAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
                row("Reservoir", String(format: "%.2f U  (%@)", units, age))
            }
        }
    }

    /// TEMPORARY DIAGNOSTIC: what the pump exposes and what has actually arrived on each
    /// characteristic. Here to answer why 669A9141 reports isNotifying but delivers nothing.
    @ViewBuilder
    private var characteristicsSection: some View {
        Section("Characteristics") {
            if bluetoothManager.characteristics.isEmpty {
                Text("None discovered yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bluetoothManager.characteristics) { characteristic in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(characteristic.shortUUID)
                                .font(.system(.subheadline, design: .monospaced))
                            Spacer()
                            Text("\(characteristic.packetCount)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(characteristic.packetCount > 0 ? .green : .secondary)
                        }

                        Text(characteristic.propertiesDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Text(characteristic.isNotifying ? "notifying" : "not notifying")
                                .font(.caption2)
                                .foregroundStyle(characteristic.isNotifying ? .green : .secondary)

                            if characteristic.subscribeAttempted && !characteristic.isNotifying {
                                Text("subscribe attempted")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        if let error = characteristic.subscribeError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }

                        if let hex = characteristic.lastPacketHex {
                            Text(hex)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
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
                    Text(event.category.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
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

/// Wraps the system share sheet so a generated CSV can be handed off to Files, Mail,
/// AirDrop or anything else the user prefers.
struct ShareSheet: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `sheet(item:)` needs an Identifiable payload, and conforming URL itself would be a
/// retroactive conformance on a Foundation type — a wrapper keeps that out of the app.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
