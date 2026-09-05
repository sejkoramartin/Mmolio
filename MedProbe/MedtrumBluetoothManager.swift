//
//  MedtrumBluetoothManager.swift
//  MedProbe
//
//  READ-ONLY CoreBluetooth transport for the Medtrum TouchCare Nano CGM stream.
//
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │ SAFETY CONTRACT                                                          │
//  │                                                                          │
//  │ This class scans, connects, discovers and subscribes. That is all.       │
//  │ It MUST NOT contain, and must never gain:                                │
//  │   • any CoreBluetooth characteristic write API, in any form              │
//  │   • any write-type or response-type argument that implies a write        │
//  │   • any pump-control, bolus, basal, alarm-ack or configuration message   │
//  │                                                                          │
//  │ CI enforces this: the "Assert no BLE write path exists" step greps the   │
//  │ whole source tree for those APIs and fails the build if any appear.      │
//  │ That is why this comment names none of them literally.                   │
//  │                                                                          │
//  │ The Medtrum EasyPatch app remains the only application that controls     │
//  │ the pump. MedProbe is a passive co-listener on an already bonded link.   │
//  └──────────────────────────────────────────────────────────────────────────┘
//

import Foundation
import CoreBluetooth

/// Connection state as shown on the diagnostic screen.
enum PumpConnectionState: String {
    case idle = "Idle"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case connected = "Connected"
    case subscribed = "Notifications enabled"
    case disconnected = "Disconnected"
}

/// Passive BLE listener for Medtrum CGM notifications.
///
/// Runs entirely on the main queue (`CBCentralManager` is created with `queue: nil`),
/// so `@Published` updates and delegate callbacks share one thread.
final class MedtrumBluetoothManager: NSObject, ObservableObject {

    // MARK: - Medtrum BLE identifiers
    //
    // Source: xDrip4iOS, CGMMedtrumTouchCareNanoTransmitter.swift
    // (JohanDegraeve/xdripswift). Not invented here, not guessed.

    /// Custom service exposed by the Medtrum patch pump.
    static let serviceUUID = CBUUID(string: "669A9001-0008-968F-E311-6050405558B3")

    /// Notification characteristic carrying CGM glucose packets. Subscribe only — never write.
    static let cgmNotifyCharacteristicUUID = CBUUID(string: "669A9141-0008-968F-E311-6050405558B3")

    /// Medtrum pumps advertise with a name starting "MT".
    static let expectedNamePrefix = "MT"

    /// Identifier for CoreBluetooth state restoration, so iOS can relaunch us for BLE events.
    static let restoreIdentifier = "cz.sejkora.MedProbe.central"

    // MARK: - published diagnostic state

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var connectionState: PumpConnectionState = .idle
    @Published private(set) var pumpName: String?
    @Published private(set) var pumpIdentifier: UUID?
    @Published private(set) var lastReading: MedtrumReading?
    @Published private(set) var lastRejectedPacketHex: String?
    @Published private(set) var lastRejectionReason: String?
    @Published private(set) var packetsReceived: Int = 0

    /// Event log rendered at the bottom of the diagnostic screen.
    let log = DiagnosticLog(category: "ble")

    // MARK: - private state

    private var centralManager: CBCentralManager?

    /// The pump we are talking to, retained so reconnects and restoration can find it again.
    private var pumpPeripheral: CBPeripheral?

    /// Delay before retrying a dropped link. EasyPatch owns the session; do not hammer it.
    private let reconnectDelay: TimeInterval = 10

    // MARK: - lifecycle

    /// Creates the central manager. Call once, as early in app launch as possible,
    /// so CoreBluetooth can hand back restored state.
    func start() {
        guard centralManager == nil else { return }

        log.info("Starting CBCentralManager (restore id \(Self.restoreIdentifier))")

        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
    }

    // MARK: - discovery

    /// Looks for the pump: first among peripherals iOS already has connected (the usual case,
    /// because EasyPatch holds the link and the pump then does not advertise), then by scanning
    /// for the Medtrum service specifically.
    private func findPump(using central: CBCentralManager) {
        if let known = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
            log.info("Found already-connected peripheral \(known.name ?? "unnamed") \(known.identifier.uuidString)")
            connect(to: known, using: central)
            return
        }

        connectionState = .scanning
        log.info("Scanning for service \(Self.serviceUUID.uuidString)")

        // Service-filtered scan: we never look at unrelated peripherals.
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    private func connect(to peripheral: CBPeripheral, using central: CBCentralManager) {
        central.stopScan()

        pumpPeripheral = peripheral
        peripheral.delegate = self
        pumpName = peripheral.name
        pumpIdentifier = peripheral.identifier
        connectionState = .connecting

        log.info("Connecting to \(peripheral.name ?? "unnamed") \(peripheral.identifier.uuidString)")

        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    private func scheduleReconnect() {
        guard let central = centralManager, let peripheral = pumpPeripheral else { return }

        log.info("Reconnect scheduled in \(Int(reconnectDelay)) s")

        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self, weak peripheral] in
            guard let self, let peripheral, central.state == .poweredOn else { return }
            guard peripheral.state == .disconnected else { return }
            self.connect(to: peripheral, using: central)
        }
    }

    // MARK: - packet handling

    private func handleNotification(_ data: Data) {
        packetsReceived += 1
        log.info("CGM packet received, \(data.count) bytes: \(MedtrumPacketDecoder.hexString(data))")

        switch MedtrumPacketDecoder.decode(data) {
        case .success(let reading):
            lastReading = reading
            lastRejectedPacketHex = nil
            lastRejectionReason = nil
            log.info(String(format: "Glucose decoded %.1f mg/dL (%.1f mmol/L) raw=%d cal=%d counter=%d",
                            reading.mgdl, reading.mmoll,
                            Int(reading.rawGlucose), Int(reading.calibrationFactor), reading.counter))

        case .failure(let error):
            lastRejectedPacketHex = MedtrumPacketDecoder.hexString(data)
            lastRejectionReason = error.localizedDescription
            log.warning("Packet rejected: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MedtrumBluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        log.info("Bluetooth state: \(central.state.displayName)")

        guard central.state == .poweredOn else {
            connectionState = .idle
            return
        }

        // A restored peripheral may already be connected; pick the setup back up from there.
        if let peripheral = pumpPeripheral, peripheral.state == .connected {
            log.info("Restored peripheral already connected, resuming service discovery")
            peripheral.delegate = self
            connectionState = .connected
            peripheral.discoverServices([Self.serviceUUID])
            return
        }

        if let peripheral = pumpPeripheral, peripheral.state == .disconnected {
            connect(to: peripheral, using: central)
            return
        }

        findPump(using: central)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        log.info("State restoration: \(restored.count) peripheral(s)")

        guard let peripheral = restored.first else { return }

        pumpPeripheral = peripheral
        peripheral.delegate = self
        pumpName = peripheral.name
        pumpIdentifier = peripheral.identifier

        log.info("Restored \(peripheral.name ?? "unnamed") \(peripheral.identifier.uuidString), state \(peripheral.state.rawValue)")
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        log.info("Discovered \(advertisedName ?? "unnamed") \(peripheral.identifier.uuidString) RSSI \(RSSI)")

        // The scan is already service-filtered; the name prefix is a second, softer check.
        // A peripheral with no name yet is accepted, because the name often only arrives on connect.
        if let advertisedName, !advertisedName.hasPrefix(Self.expectedNamePrefix) {
            log.warning("Ignoring \(advertisedName): name does not start with \(Self.expectedNamePrefix)")
            return
        }

        connect(to: peripheral, using: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        pumpName = peripheral.name ?? pumpName
        log.info("Connected to \(peripheral.name ?? "unnamed"), discovering services")

        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        log.error("Failed to connect: \(error?.localizedDescription ?? "no error given")")
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        log.warning("Disconnected: \(error?.localizedDescription ?? "clean disconnect")")
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension MedtrumBluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log.error("Service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            log.error("Medtrum service \(Self.serviceUUID.uuidString) not present on peripheral")
            return
        }

        log.info("Service discovered \(service.uuid.uuidString), discovering characteristics")
        peripheral.discoverCharacteristics([Self.cgmNotifyCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            log.error("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let characteristic = service.characteristics?
            .first(where: { $0.uuid == Self.cgmNotifyCharacteristicUUID }) else {
            log.error("CGM characteristic \(Self.cgmNotifyCharacteristicUUID.uuidString) not found")
            return
        }

        log.info("Characteristic discovered \(characteristic.uuid.uuidString), properties \(characteristic.properties.rawValue)")

        // The only action MedProbe ever takes on a characteristic: subscribe.
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log.error("Enabling notifications failed: \(error.localizedDescription)")
            return
        }

        if characteristic.isNotifying {
            connectionState = .subscribed
            log.info("Notifications enabled on \(characteristic.uuid.uuidString)")
        } else {
            connectionState = .connected
            log.warning("Notifications disabled on \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log.error("Notification error: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == Self.cgmNotifyCharacteristicUUID else { return }
        guard let value = characteristic.value else { return }

        handleNotification(value)
    }
}

// MARK: - display helpers

extension CBManagerState {

    /// Human-readable name for the diagnostic screen.
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "Off"
        case .poweredOn: return "On"
        @unknown default: return "Unhandled (\(rawValue))"
        }
    }
}
