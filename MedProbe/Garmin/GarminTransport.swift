//
//  GarminTransport.swift
//  MedProbe
//
//  Sending readings to a Garmin watch.
//
//  Delivery uses Garmin's Connect IQ Companion App SDK, added as a Swift package from
//  their public repository (garmin/connectiq-companion-app-sdk-ios). The real transport
//  lives in ConnectIQTransport.swift.
//
//  This protocol still exists so the rest of the app — and its tests — never depend on
//  that binary, and so the pipeline can be exercised without a watch present.
//

import Foundation
import Combine

/// A Garmin watch MedProbe can send to.
struct GarminDevice: Equatable, Identifiable, Codable {

    /// Connect IQ device identifier.
    let id: UInt64

    /// Model name as reported by the SDK, e.g. "Forerunner 255".
    let name: String

    /// Whether the phone currently has a usable link to it.
    var isConnected: Bool

    /// Product identifiers of the watches this project ships watch faces for.
    /// Used only for display hints — sending is not restricted to this list.
    static let knownSupportedModels = ["Forerunner 255", "Forerunner 165"]

    var isKnownSupported: Bool {
        Self.knownSupportedModels.contains { name.localizedCaseInsensitiveContains($0) }
    }
}

enum GarminTransportError: Error, Equatable {
    case sdkUnavailable
    case noDeviceSelected
    case deviceNotConnected
    case appNotInstalled
    case sendFailed(String)

    var userFacingDescription: String {
        switch self {
        case .sdkUnavailable:
            return "Connect IQ SDK is not part of this build"
        case .noDeviceSelected:
            return "No watch selected"
        case .deviceNotConnected:
            return "Watch is not connected"
        case .appNotInstalled:
            return "MedProbe watch app is not installed"
        case .sendFailed(let detail):
            return "Send failed: \(detail)"
        }
    }
}

/// Delivers glucose readings to a watch.
///
/// The protocol exists so the rest of the app — and its tests — never depend on the
/// Connect IQ binary. Swapping in the real implementation changes one line of wiring.
protocol GarminTransport: AnyObject {

    /// Watches the SDK currently knows about.
    var devices: [GarminDevice] { get }
    var devicesPublisher: AnyPublisher<[GarminDevice], Never> { get }

    /// The watch messages are sent to.
    var selectedDevice: GarminDevice? { get }
    func select(_ device: GarminDevice?)

    /// When the last message was accepted for delivery, and what went wrong last.
    var lastSentAt: Date? { get }
    var lastError: GarminTransportError? { get }

    /// Begin or end discovering watches.
    func start()
    func stop()

    /// Opens Garmin Connect so the user can grant this app access to their watches.
    /// Nothing appears in `devices` until they have done this at least once.
    func requestDevices()

    /// Handles the callback Garmin Connect makes when it hands control back.
    /// Without this the selection completes on their side and never reaches ours.
    func handleReturn(from url: URL)

    /// Sends a reading. Duplicate and out-of-order suppression happens here, so callers
    /// can hand over every reading they receive.
    func send(_ reading: GlucoseReading, completion: @escaping (Result<Void, GarminTransportError>) -> Void)
}

/// Stand-in transport for builds without the Connect IQ package, and for tests.
///
/// Records what would have been sent, applies the real send policy, and reports the SDK
/// as unavailable. It keeps the pipeline exercisable without pretending a watch received
/// anything.
final class UnavailableGarminTransport: GarminTransport {

    private(set) var devices: [GarminDevice] = []
    private(set) var selectedDevice: GarminDevice?
    private(set) var lastSentAt: Date?
    private(set) var lastError: GarminTransportError? = .sdkUnavailable

    /// Messages that passed the send policy. Inspectable by tests and by the diagnostic UI.
    private(set) var acceptedMessages: [GarminMessage] = []

    var devicesPublisher: AnyPublisher<[GarminDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    private let devicesSubject = CurrentValueSubject<[GarminDevice], Never>([])
    private var policy = GarminSendPolicy()

    func select(_ device: GarminDevice?) {
        selectedDevice = device
    }

    func start() {}
    func stop() {}
    func requestDevices() {}
    func handleReturn(from url: URL) {}

    func send(_ reading: GlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {

        // The policy still runs, so its behaviour is exercised in every build even while
        // the SDK is missing. A message that would be skipped is not counted as an error.
        switch policy.decide(reading) {
        case .skipDuplicate, .skipOlder:
            completion(.success(()))
            return
        case .send:
            acceptedMessages.append(GarminMessage(reading: reading))
        }

        lastError = .sdkUnavailable
        completion(.failure(.sdkUnavailable))
    }
}
