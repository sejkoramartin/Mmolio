//
//  GlucoseCoordinator.swift
//  MedProbe
//
//  Owns the active glucose source and forwards its readings to the watch.
//
//  The source is chosen by the user, not hardcoded: nothing here knows that Medtrum
//  "belongs to" one watch or Libre to another. Any source can feed any watch.
//

import Foundation
import Combine

/// Which source is currently selected.
enum SelectedSource: String, CaseIterable, Identifiable {
    case medtrum
    case libreLinkUp

    var id: String { rawValue }

    var kind: GlucoseSourceKind {
        switch self {
        case .medtrum: return .medtrum
        case .libreLinkUp: return .libreLinkUp
        }
    }

    var displayName: String { kind.displayName }

    static let storageKey = "medprobe.selectedSource"

    static var current: SelectedSource {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = SelectedSource(rawValue: raw) else { return .medtrum }
        return value
    }
}

/// Connects the selected source to the Garmin transport.
final class GlucoseCoordinator: ObservableObject {

    @Published private(set) var selected: SelectedSource
    @Published private(set) var latestReading: GlucoseReading?
    @Published private(set) var sourceState: GlucoseSourceState = .idle
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastSendError: GarminTransportError?

    /// Watches the transport knows about, republished here because GarminTransport is a
    /// protocol rather than an ObservableObject and SwiftUI needs something to observe.
    @Published private(set) var watches: [GarminDevice] = []
    @Published private(set) var selectedWatch: GarminDevice?

    private let medtrum: MedtrumSource
    private let libre: LibreLinkUpSource
    private let transport: GarminTransport
    private let heartbeat: LibreHeartbeatListener
    private let log: DiagnosticLog

    private var cancellables = Set<AnyCancellable>()

    /// Separate from `cancellables`, which is cleared on every source switch.
    private var transportCancellables = Set<AnyCancellable>()

    init(medtrum: MedtrumSource,
         libre: LibreLinkUpSource,
         transport: GarminTransport,
         heartbeat: LibreHeartbeatListener,
         log: DiagnosticLog) {
        self.medtrum = medtrum
        self.libre = libre
        self.transport = transport
        self.heartbeat = heartbeat
        self.log = log
        self.selected = SelectedSource.current

        // The heartbeat is only ever a prompt to fetch. It never carries a value.
        heartbeat.onHeartbeat = { [weak self] _ in
            self?.libre.requestImmediateFetch(reason: "Libre heartbeat")
        }

        transport.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.watches = devices
                self?.selectedWatch = self?.transport.selectedDevice
            }
            .store(in: &transportCancellables)
    }

    /// Opens Garmin Connect so the user can grant access to their watches.
    func findWatches() {
        log.info("Garmin: opening Connect for device selection", .diagnostic)
        transport.requestDevices()
    }

    /// Passes the callback from Garmin Connect back to the transport.
    func handleGarminReturn(from url: URL) {
        transport.handleReturn(from: url)
    }

    /// Chooses which watch receives readings.
    func selectWatch(_ device: GarminDevice?) {
        transport.select(device)
        selectedWatch = device
    }

    var activeSource: CGMSource {
        selected == .medtrum ? medtrum : libre
    }

    func start() {
        transport.start()
        activate(selected)
    }

    /// Switches source. The inactive one is stopped so two sources never compete to send.
    func select(_ source: SelectedSource) {
        guard source != selected else { return }

        log.info("Glucose source: \(selected.displayName) -> \(source.displayName)", .diagnostic)
        UserDefaults.standard.set(source.rawValue, forKey: SelectedSource.storageKey)

        deactivateAll()
        selected = source
        latestReading = nil
        activate(source)
    }

    private func activate(_ source: SelectedSource) {
        cancellables.removeAll()

        let active: CGMSource = source == .medtrum ? medtrum : libre

        active.readingPublisher
            .sink { [weak self] reading in self?.handle(reading) }
            .store(in: &cancellables)

        active.statePublisher
            .sink { [weak self] state in self?.sourceState = state }
            .store(in: &cancellables)

        active.start()
        sourceState = active.state

        if source == .libreLinkUp && LibreHeartbeatListener.isEnabled {
            heartbeat.start()
        }
    }

    private func deactivateAll() {
        cancellables.removeAll()
        medtrum.stop()
        libre.stop()
        heartbeat.stop()
    }

    private func handle(_ reading: GlucoseReading) {
        latestReading = reading

        // Delivery to the watch goes over Bluetooth and takes a moment. If the app is in
        // the background — which is most of the time, since nobody watches this screen —
        // it needs to stay awake until the send completes or fails.
        let work = BackgroundWork("Send to watch", log: log)
        work.begin()

        transport.send(reading) { [weak self] result in
            DispatchQueue.main.async {
                defer { work.end() }

                switch result {
                case .success:
                    self?.lastSentAt = Date()
                    self?.lastSendError = nil
                case .failure(let error):
                    self?.lastSendError = error
                    self?.log.warning("Garmin: \(error.userFacingDescription)", .diagnostic)
                }
            }
        }
    }

    /// Sends the most recent reading again, for the settings screen's test button.
    func sendTestReading(completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        guard let reading = latestReading else {
            completion(.failure(.sendFailed("no reading to send yet")))
            return
        }
        transport.send(reading, completion: completion)
    }

    /// Turns the experimental heartbeat on or off at runtime.
    func setHeartbeatEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: LibreHeartbeatListener.enabledKey)

        if enabled && selected == .libreLinkUp {
            heartbeat.start()
        } else {
            heartbeat.stop()
        }
    }
}
