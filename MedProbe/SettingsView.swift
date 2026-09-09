//
//  SettingsView.swift
//  MedProbe
//
//  Choosing where readings come from and where they go.
//
//  Sections are separate computed properties rather than one long body: SwiftUI's builder
//  takes at most ten children, and small pieces are easier to read anyway.
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject var coordinator: GlucoseCoordinator
    let credentials: LibreCredentials

    @AppStorage(SelectedSource.storageKey) private var selectedSource = SelectedSource.medtrum.rawValue
    @AppStorage(LibreHeartbeatListener.enabledKey) private var heartbeatEnabled = false

    @State private var email = ""
    @State private var password = ""
    @State private var region = LibreRegion.europe
    @State private var isSignedIn = false
    @State private var statusMessage: String?
    @State private var isConfirmingHeartbeat = false

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                libreSection
                watchSection
                activitySection
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadStoredCredentials)
        }
    }

    // MARK: - source

    private var sourceSection: some View {
        Section("Glucose source") {
            Picker("Source", selection: $selectedSource) {
                ForEach(SelectedSource.allCases) { source in
                    Text(source.displayName).tag(source.rawValue)
                }
            }
            .onChange(of: selectedSource) { _, newValue in
                guard let source = SelectedSource(rawValue: newValue) else { return }
                coordinator.select(source)
            }

            LabeledContent("Status") {
                Text(stateDescription)
                    .foregroundStyle(stateColour)
            }

            if let reading = coordinator.latestReading {
                LabeledContent("Last reading") {
                    Text(String(format: "%.1f mmol/L %@", reading.mmoll, reading.trend.arrow))
                        .monospacedDigit()
                }
            }
        }
    }

    private var stateDescription: String {
        switch coordinator.sourceState {
        case .disabled: return "Off"
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .failed(let error): return error.userFacingDescription
        }
    }

    private var stateColour: Color {
        switch coordinator.sourceState {
        case .connected: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }

    // MARK: - LibreLinkUp

    @ViewBuilder
    private var libreSection: some View {
        Section("LibreLinkUp") {
            if isSignedIn {
                LabeledContent("Signed in as", value: credentials.email ?? "—")
                LabeledContent("Region", value: credentials.region.displayName)

                Button("Sign out", role: .destructive) {
                    credentials.clearAll()
                    isSignedIn = false
                    email = ""
                    password = ""
                    statusMessage = "Signed out."
                }
            } else {
                Picker("Region", selection: $region) {
                    ForEach(LibreRegion.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }

                Text("Only a hint — MedProbe asks the service where the account lives and follows it. Picking the wrong one here is not fatal.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)

                Button("Sign in") { signIn() }
                    .disabled(email.isEmpty || password.isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("MedProbe reads what the official Libre app has already uploaded. It never touches the sensor, and it is not a replacement for the Libre app's alarms.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            heartbeatToggle
        }
    }

    private var heartbeatToggle: some View {
        Toggle(isOn: Binding(
            get: { heartbeatEnabled },
            set: { newValue in
                if newValue {
                    isConfirmingHeartbeat = true
                } else {
                    heartbeatEnabled = false
                    coordinator.setHeartbeatEnabled(false)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Faster Libre updates")
                Text("Experimental. Listens for the sensor's Bluetooth notifications and uses them only as a prompt to fetch — it never reads glucose from them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Enable experimental listening?", isPresented: $isConfirmingHeartbeat) {
            Button("Cancel", role: .cancel) { }
            Button("Enable") {
                heartbeatEnabled = true
                coordinator.setHeartbeatEnabled(true)
            }
        } message: {
            Text("MedProbe will attach to the sensor connection your Libre app already has, read-only, to notice when a new value exists. If the Libre app behaves oddly at all, switch this off. Glucose still comes from LibreLinkUp.")
        }
    }

    // MARK: - watch

    @ViewBuilder
    private var watchSection: some View {
        Section("Garmin watch") {
            if coordinator.watches.isEmpty {
                Text("No watches found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.watches) { device in
                    Button {
                        coordinator.selectWatch(device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.isConnected ? "Connected" : "Not connected")
                                    .font(.caption2)
                                    .foregroundStyle(device.isConnected ? .green : .secondary)
                            }
                            Spacer()
                            if coordinator.selectedWatch?.id == device.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Send a test reading") { sendTest() }
                .disabled(coordinator.latestReading == nil)

            if let error = coordinator.lastSendError {
                Text(error.userFacingDescription)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - activity

    private var activitySection: some View {
        Section("Activity") {
            LabeledContent("Last reading at") {
                Text(coordinator.latestReading.map { Self.formatter.string(from: $0.measuredAt) } ?? "—")
                    .monospacedDigit()
            }
            LabeledContent("Last sent to watch") {
                Text(coordinator.lastSentAt.map { Self.formatter.string(from: $0) } ?? "—")
                    .monospacedDigit()
            }
        }
    }

    // MARK: - actions

    private func loadStoredCredentials() {
        isSignedIn = credentials.hasLogin
        email = credentials.email ?? ""
        region = credentials.region
    }

    private func signIn() {
        // Only the credentials are stored here; the source signs in on its next fetch and
        // reports the outcome through its state, so a wrong password surfaces there.
        //
        // The result is checked rather than assumed. A Keychain write that fails silently
        // used to leave the form looking signed in while the source reported no account
        // configured, with nothing connecting the two.
        switch credentials.storeLogin(email: email, password: password, region: region) {
        case .success:
            isSignedIn = true
            password = ""
            statusMessage = "Saved. Select LibreLinkUp as the source to connect."

        case .failure(let error):
            isSignedIn = false
            statusMessage = "Could not save to the Keychain: \(error.diagnosticDescription). Nothing was stored."
        }
    }

    private func sendTest() {
        coordinator.sendTestReading { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    statusMessage = "Test reading sent."
                case .failure(let error):
                    statusMessage = error.userFacingDescription
                }
            }
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
