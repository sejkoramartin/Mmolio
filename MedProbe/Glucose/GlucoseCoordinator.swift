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

    private let medtrum: MedtrumSource
    private let libre: LibreLinkUpSource
    private let transport: GarminTransport
    private let heartbeat: LibreHeartbeatListener
    private let log: DiagnosticLog

    private var cancellables = Set<AnyCancellable>()

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

        transport.send(reading) { [weak self] result in
            DispatchQueue.main.async {
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
