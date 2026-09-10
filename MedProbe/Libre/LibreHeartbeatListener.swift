//
//  LibreHeartbeatListener.swift
//  MedProbe
//
//  EXPERIMENTAL. Off by default.
//
//  ┌──────────────────────────────────────────────────────────────────────────────────┐
//  │ WHAT THIS IS                                                                     │
//  │                                                                                  │
//  │ A Libre 2+ sensor notifies its paired phone roughly once a minute. The official  │
//  │ Libre app owns that link and decodes those notifications. This listener attaches  │
//  │ to the same already-connected peripheral and subscribes to the same notification  │
//  │ characteristic — and uses the arrival of a notification as nothing more than a    │
//  │ hint that LibreLinkUp may now have a fresher value worth fetching.                │
//  │                                                                                  │
//  │ It never decodes the packet. Libre 2+ payloads are encrypted, decoding them would │
//  │ mean deriving keys from the sensor, and that is exactly the line this project     │
//  │ does not cross. The glucose value always comes from LibreLinkUp.                  │
//  │                                                                                  │
//  │ WHAT IT MUST NEVER DO                                                            │
//  │                                                                                  │
//  │   • write to F001 or any other characteristic                                     │
//  │   • send an unlock or enable-streaming command                                    │
//  │   • scan or write NFC                                                             │
//  │   • decode a packet as a glucose source                                           │
//  │   • disconnect, or otherwise disturb, the official Libre app                      │
//  │                                                                                  │
//  │ The safeguard is structural: this type holds a CBPeripheral but exposes no method │
//  │ that writes, and the CI guard rejects the write APIs across the whole source      │
//  │ tree. Subscribing enables a notification; it does not command the sensor.         │
//  └──────────────────────────────────────────────────────────────────────────────────┘
//
//  Any failure here is silent and falls back to ordinary LibreLinkUp polling. This
//  listener is an optimisation, never a dependency.
//

import Foundation
import CoreBluetooth

/// Watches for Libre notification traffic and reports that something arrived.
///
/// Deliberately does not own the fetch: it calls back, and the caller decides whether a
/// fetch is due. That keeps rate limiting in one place.
final class LibreHeartbeatListener: NSObject {

    /// Abbott's sensor service. Discovery is filtered to it, so no other peripheral is
    /// ever examined.
    static let serviceUUID = CBUUID(string: "FDE3")

    /// The notification characteristic. This is the only one subscribed to.
    static let notifyCharacteristicUUID = CBUUID(string: "F002")

    /// The sensor's write characteristic, named here **only** so it can be excluded by
    /// name and so a reader can see it was considered. Nothing in this file writes to it.
    static let excludedCharacteristicUUID = CBUUID(string: "F001")

    /// CoreBluetooth state restoration identifier. Distinct from the Medtrum one: two
    /// central managers in one app must not share it.
    static let restoreIdentifier = "cz.sejkora.MedProbe.libreHeartbeat"

    /// Feature flag key. Off unless the user deliberately turns it on.
    static let enabledKey = "medprobe.libreHeartbeatEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Called when a notification arrives. Carries no packet contents: the payload is
    /// deliberately not passed on, so it cannot become a glucose source by accident.
    var onHeartbeat: ((Date) -> Void)?

    private(set) var isListening = false
    private(set) var heartbeatCount = 0
    private(set) var lastHeartbeatAt: Date?

    /// A sensor dropping and coming back is ordinary. Retrying is therefore necessary —
    /// but slowly and with a ceiling, because the link belongs to the Libre app and a
    /// listener that grabs at it repeatedly is exactly the interference to avoid.
    private static let reattachDelays: [TimeInterval] = [30, 60, 120, 300]
    private var reattachAttempt = 0
    private var reattachGeneration = 0

    private let log: DiagnosticLog
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    init(log: DiagnosticLog) {
        self.log = log
        super.init()
    }

    // MARK: - lifecycle

    func start() {
        guard Self.isEnabled else {
            log.info("Libre heartbeat: disabled", .ble)
            return
        }
        guard central == nil else { return }

        log.info("Libre heartbeat: starting (experimental, read-only)", .ble)

        // The restore identifier is what lets iOS deliver these notifications to a
        // suspended app, and relaunch it if the app was terminated. Without it the
        // listener works only while MedProbe is on screen — which defeats the point,
        // since the whole reason it exists is to keep the watch current while the phone
        // is in a pocket.
        //
        // It still only ever subscribes, and it still falls back silently to polling.
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
    }

    func stop() {
        // Nothing to report if it was never running: the coordinator calls stop() on
        // every source switch, and logging "stopped" each time is noise that reads like
        // something went wrong.
        guard central != nil else { return }

        if let peripheral, let central {
            // Unsubscribe before letting go, so nothing is left enabled on a link the
            // official app owns.
            if let characteristic = peripheral.services?
                .first(where: { $0.uuid == Self.serviceUUID })?
                .characteristics?
                .first(where: { $0.uuid == Self.notifyCharacteristicUUID }),
               characteristic.isNotifying {
                peripheral.setNotifyValue(false, for: characteristic)
            }
            central.cancelPeripheralConnection(peripheral)
        }

        peripheral = nil
        central = nil
        isListening = false
        // Invalidate any pending retry, or a stopped listener quietly comes back.
        reattachGeneration += 1
        reattachAttempt = 0
        log.info("Libre heartbeat: stopped", .ble)
    }

    /// Attaches to a sensor iOS already has connected.
    ///
    /// Only `retrieveConnectedPeripherals` is used — never a scan. If the official app is
    /// not connected to a sensor, there is nothing to attach to and this does nothing.
    private func attachToConnectedSensor(_ central: CBCentralManager) {
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])

        guard let sensor = connected.first else {
            log.info("Libre heartbeat: no connected sensor found; polling continues normally", .ble)
            return
        }

        log.info("Libre heartbeat: attaching to \(sensor.identifier.uuidString.prefix(8))", .ble)
        peripheral = sensor
        sensor.delegate = self

        if sensor.state == .connected {
            centralManager(central, didConnect: sensor)
        } else {
            central.connect(sensor, options: nil)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension LibreHeartbeatListener: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }

        // A restored peripheral is already connected; carry on from there rather than
        // looking for it again.
        if let peripheral, peripheral.state == .connected {
            peripheral.delegate = self
            self.centralManager(central, didConnect: peripheral)
            return
        }

        attachToConnectedSensor(central)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let sensor = restored.first else { return }

        log.info("Libre heartbeat: restored by iOS", .ble)
        peripheral = sensor
        sensor.delegate = self
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isListening = false
        log.info("Libre heartbeat: sensor disconnected; polling continues while we retry", .ble)
        scheduleReattach(using: central)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log.info("Libre heartbeat: could not attach; polling continues normally", .ble)
        scheduleReattach(using: central)
    }

    /// Tries again later, backing off and eventually settling at five minutes.
    ///
    /// Unbounded retrying would be interference; never retrying means one ordinary sensor
    /// dropout ends the heartbeat for good, which is what happened overnight — five hours
    /// with nothing but a poll timer that a suspended app never runs.
    private func scheduleReattach(using central: CBCentralManager) {
        guard Self.isEnabled else { return }

        let delay = Self.reattachDelays[min(reattachAttempt, Self.reattachDelays.count - 1)]
        reattachAttempt += 1
        reattachGeneration += 1
        let generation = reattachGeneration

        log.info("Libre heartbeat: retrying in \(Int(delay))s", .ble)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reattachGeneration == generation else { return }
            guard Self.isEnabled, central.state == .poweredOn else { return }
            guard !self.isListening else { return }

            self.attachToConnectedSensor(central)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension LibreHeartbeatListener: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            log.info("Libre heartbeat: sensor service not available", .ble)
            return
        }
        // Only the notification characteristic is asked for. F001 is never discovered,
        // so there is not even a handle to write to.
        peripheral.discoverCharacteristics([Self.notifyCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil,
              let characteristic = service.characteristics?
                .first(where: { $0.uuid == Self.notifyCharacteristicUUID }) else {
            log.info("Libre heartbeat: notification characteristic not available", .ble)
            return
        }

        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log.info("Libre heartbeat: subscribe refused (\(error.localizedDescription)); polling continues", .ble)
            return
        }
        isListening = characteristic.isNotifying
        if isListening {
            reattachAttempt = 0
        }
        log.info("Libre heartbeat: listening=\(isListening)", .ble)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, characteristic.uuid == Self.notifyCharacteristicUUID else { return }

        // The payload is deliberately ignored. Its length is not even recorded, so there
        // is no path by which it could become a glucose value.
        heartbeatCount += 1
        lastHeartbeatAt = Date()

        // The callback starts a network fetch. Hold background time across it, or a
        // wake-up in the user's pocket is cut off before it achieves anything.
        let work = BackgroundWork("Libre heartbeat", log: log)
        work.begin()
        onHeartbeat?(Date())
        // The fetch takes its own background assertion; this one only has to cover
        // handing the work over.
        work.end()
    }
}
