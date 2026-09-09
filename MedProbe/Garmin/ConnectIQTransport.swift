//
//  ConnectIQTransport.swift
//  MedProbe
//
//  The real Garmin transport, behind a compile-time check.
//
//  The Connect IQ package comes from Garmin's public repository and is declared in
//  project.yml, so a normal build has it. The canImport guard remains so the project
//  still compiles if the package is ever removed or fails to resolve, falling back to
//  the stand-in transport rather than failing outright.
//
//  Nothing here is Medtrum- or Libre-specific: it sends whatever GlucoseReading it is
//  given, to whichever watch is selected.
//

import Foundation
import Combine

#if canImport(ConnectIQ)
import ConnectIQ

/// Sends readings to a Garmin watch over the Connect IQ Mobile SDK.
final class ConnectIQTransport: NSObject, GarminTransport {

    /// Must match the application id in garmin/MedProbeWatch/manifest.xml. The watch app
    /// and the phone find each other by this and nothing else.
    ///
    /// Connect IQ writes it as 32 bare hex characters. Foundation's UUID parser requires
    /// the 8-4-4-4-12 hyphenated form and returns nil for anything else — which is not an
    /// error anyone sees, because IQApp accepts a nil uuid and then quietly addresses
    /// nothing. Messages sent to it fail with a timeout, several seconds later, with no
    /// hint of the cause.
    static let watchAppID = "a1b2c3d4e5f647589a0b1c2d3e4f5061"

    /// The app id as Foundation needs it.
    static var watchAppUUID: UUID? {
        ConnectIQAppID.uuid(from: watchAppID)
    }

    /// URL scheme the SDK uses to hand control back after device selection. Also declared
    /// in Info.plist; the two must agree or the return trip silently fails.
    static let returnURLScheme = "medprobe"

    private(set) var devices: [GarminDevice] = [] {
        didSet { devicesSubject.send(devices) }
    }
    private(set) var selectedDevice: GarminDevice?
    private(set) var lastSentAt: Date?
    private(set) var lastError: GarminTransportError?

    var devicesPublisher: AnyPublisher<[GarminDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }
    private let devicesSubject = CurrentValueSubject<[GarminDevice], Never>([])

    private var policy = GarminSendPolicy()
    private var knownDevices: [UInt64: IQDevice] = [:]

    /// Stable identity for a device.
    ///
    /// Not hashValue: Swift seeds hashing per process, so it changes on every launch and
    /// the remembered watch would never be found again. The first eight bytes of the
    /// device UUID are stable and unique enough to tell two watches apart.
    private static func identity(of device: IQDevice) -> UInt64 {
        withUnsafeBytes(of: device.uuid.uuid) { raw in
            raw.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
    }
    private var watchApps: [UInt64: IQApp] = [:]
    private let log: DiagnosticLog

    /// Selected watch survives relaunch; without it the user would re-pick every time.
    private static let selectedDeviceKey = "medprobe.selectedGarminDevice"

    init(log: DiagnosticLog) {
        self.log = log
        super.init()
    }

    func start() {
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.returnURLScheme,
                                              uiOverrideDelegate: nil)
        restoreKnownDevices()
    }

    func stop() {
        for device in knownDevices.values {
            ConnectIQ.sharedInstance().unregister(forDeviceEvents: device, delegate: self)
        }
        for app in watchApps.values {
            ConnectIQ.sharedInstance().unregister(forAppMessages: app, delegate: self)
        }
    }

    func select(_ device: GarminDevice?) {
        selectedDevice = device
        UserDefaults.standard.set(Int64(bitPattern: device?.id ?? 0), forKey: Self.selectedDeviceKey)
        // Sequence numbers are not comparable across watches any more than across
        // sources: a new watch has seen nothing and must receive the next reading.
        policy.reset()
    }

    /// Opens Garmin Connect so the user can choose which watches to expose.
    func requestDevices() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Handles the callback from Garmin Connect after device selection.
    func handleReturn(from url: URL) {
        guard let returned = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url)
                as? [IQDevice] else { return }

        log.info("Garmin: \(returned.count) device(s) returned from selection", .diagnostic)
        register(returned)
    }

    private func restoreKnownDevices() {
        // The SDK only reports devices the user has already exposed to this app, so there
        // is nothing to restore until they have been through selection at least once.
        register(Array(knownDevices.values))
    }

    private func register(_ found: [IQDevice]) {
        for device in found {
            let id = Self.identity(of: device)
            knownDevices[id] = device
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)

            guard let appUUID = Self.watchAppUUID else {
                // Refuse rather than address nothing: a nil uuid produces a timeout
                // minutes later that says nothing about the real problem.
                log.error("Garmin: watch app id '\(Self.watchAppID)' is not a valid UUID", .diagnostic)
                continue
            }

            if let app = IQApp(uuid: appUUID, store: nil, device: device) {
                watchApps[id] = app
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
            }
        }
        refreshDeviceList()

        // Reselect what the user picked last time.
        let storedID = UInt64(bitPattern: Int64(UserDefaults.standard.integer(forKey: Self.selectedDeviceKey)))
        if selectedDevice == nil, storedID != 0 {
            selectedDevice = devices.first { $0.id == storedID }
        }

        // With exactly one watch there is nothing to choose between, and leaving it
        // unselected means readings are silently dropped while the screen shows the watch
        // as connected — which is precisely what happened on the device.
        if selectedDevice == nil, devices.count == 1, let only = devices.first {
            log.info("Garmin: selecting \(only.name), the only watch available", .diagnostic)
            select(only)
        }
    }

    private func refreshDeviceList() {
        devices = knownDevices.map { id, device in
            GarminDevice(
                id: id,
                name: device.friendlyName ?? device.modelName ?? "Garmin",
                isConnected: ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected
            )
        }
        .sorted { $0.name < $1.name }
    }

    func send(_ reading: GlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {

        switch policy.decide(reading) {
        case .skipDuplicate, .skipOlder:
            // Not an error: the watch already has this, and waking it again costs battery
            // on both ends.
            completion(.success(()))
            return
        case .send:
            break
        }

        guard let selected = selectedDevice else {
            fail(.noDeviceSelected, completion); return
        }
        guard let device = knownDevices[selected.id], let app = watchApps[selected.id] else {
            fail(.appNotInstalled, completion); return
        }
        guard ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected else {
            fail(.deviceNotConnected, completion); return
        }

        let payload = GarminMessage(reading: reading).encoded()

        ConnectIQ.sharedInstance().sendMessage(payload, to: app, progress: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if result == .success {
                    self.lastSentAt = Date()
                    self.lastError = nil
                    completion(.success(()))
                } else {
                    // The reading was not delivered, so the policy must forget it or the
                    // retry would be suppressed as a duplicate.
                    self.policy.reset()
                    self.fail(.sendFailed(Self.describe(result)), completion)
                }
            }
        }
    }

    /// Turns a Connect IQ result into something that says what to do about it.
    static func describe(_ result: IQSendMessageResult) -> String {
        switch result {
        case .success: return "sent"
        case .failure_Unknown: return "unknown error"
        case .failure_InternalError: return "internal error in the SDK or on the watch"
        case .failure_DeviceNotAvailable: return "watch not available"
        case .failure_AppNotFound: return "MedProbe is not installed on the watch"
        case .failure_DeviceIsBusy: return "watch is busy"
        case .failure_UnsupportedType: return "message contained an unsupported type"
        case .failure_InsufficientMemory: return "watch is out of memory"
        case .failure_Timeout: return "timed out — is MedProbe open on the watch, and does its app id match?"
        case .failure_MaxRetries: return "gave up after several retries"
        case .failure_PromptNotDisplayed: return "watch ignored the message"
        case .failure_AppAlreadyRunning: return "app already running"
        @unknown default: return "Connect IQ result \(result.rawValue)"
        }
    }

    private func fail(_ error: GarminTransportError,
                      _ completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        lastError = error
        log.warning("Garmin: \(error.userFacingDescription)", .diagnostic)
        completion(.failure(error))
    }
}

extension ConnectIQTransport: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        refreshDeviceList()
        log.info("Garmin: \(device.friendlyName ?? "watch") is \(status == .connected ? "connected" : "not connected")", .diagnostic)
    }
}

extension ConnectIQTransport: IQAppMessageDelegate {
    func receivedMessage(_ message: Any, from app: IQApp) {
        // The watch is not expected to send anything back. Logged rather than ignored so
        // an unexpected message is visible instead of silently dropped.
        log.info("Garmin: unexpected message from the watch app", .diagnostic)
    }
}

#endif

/// Builds the transport that suits this build.
///
/// One place decides, so the rest of the app never asks whether the SDK is present.
enum GarminTransportFactory {

    static func make(log: DiagnosticLog) -> GarminTransport {
        #if canImport(ConnectIQ)
        return ConnectIQTransport(log: log)
        #else
        return UnavailableGarminTransport()
        #endif
    }

    /// Whether this build can actually reach a watch.
    static var isAvailable: Bool {
        #if canImport(ConnectIQ)
        return true
        #else
        return false
        #endif
    }
}
