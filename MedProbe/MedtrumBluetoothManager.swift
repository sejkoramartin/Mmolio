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
    ///
    /// Note: physical testing found this characteristic subscribes successfully and then
    /// never delivers anything on this pump. It is kept subscribed and decoded in case it
    /// becomes active, but the live traffic is on the two below.
    static let cgmNotifyCharacteristicUUID = CBUUID(string: "669A9141-0008-968F-E311-6050405558B3")

    /// AndroidAPS READ_UUID: the pump's field-mask notification stream.
    static let notificationCharacteristicUUID = CBUUID(string: "669A9120-0008-968F-E311-6050405558B3")

    /// AndroidAPS WRITE_UUID: fragmented replies. AndroidAPS both sends commands here and
    /// reads the answers; MedProbe only ever watches the answers EasyPatch provokes.
    static let fragmentStreamCharacteristicUUID = CBUUID(string: "669A9101-0008-968F-E311-6050405558B3")

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

    /// TEMPORARY DIAGNOSTIC: every characteristic found on the pump, with per-characteristic
    /// notification counts. Present to answer why notifications never arrived on 669A9141.
    @Published private(set) var characteristics: [DiagnosticCharacteristic] = []

    /// Most recent parsed 669A9120 notification.
    @Published private(set) var lastNotification: MedtrumNotification?

    /// First byte of the CGM field in the most recent 669A9120 notification, and when it
    /// last changed. Surfaced because it is currently our only visible predictor of
    /// whether 669A9141 will deliver anything.
    @Published private(set) var cgmStateByte: UInt8?
    @Published private(set) var cgmStateChangedAt: Date?

    /// Last reported reservoir level in units, and when it arrived. Kept separately because
    /// notifications do not carry this field every time, so the latest known value should
    /// survive the ones that omit it.
    @Published private(set) var reservoirUnits: Double?
    @Published private(set) var reservoirUpdatedAt: Date?

    /// Most recent fully reassembled 669A9101 message.
    @Published private(set) var lastAssembledFrame: AssembledFrame?

    /// Completed reassemblies this session.
    @Published private(set) var assembledFrameCount: Int = 0

    // MARK: - stream health metrics

    /// When the last valid CGM packet arrived.
    @Published private(set) var lastValidCGMPacketAt: Date?

    /// Live CGM readings delivered this session.
    @Published private(set) var cgmReadingCount: Int = 0

    /// Readings recovered from packet history slots.
    @Published private(set) var backfilledReadingCount: Int = 0

    /// Cycles the counter says we never saw, live or backfilled.
    @Published private(set) var missedCycleCount: Int = 0

    /// Whether 669A9141 currently reports itself as notifying.
    @Published private(set) var isCGMCharacteristicNotifying = false

    /// Readings recovered by the most recent backfill, newest last.
    @Published private(set) var lastBackfilled: [BackfilledReading] = []

    /// Reconnects performed this session, and why the last one happened.
    @Published private(set) var reconnectCount: Int = 0
    @Published private(set) var lastReconnectReason: ReconnectReason?
    @Published private(set) var lastReconnectAt: Date?

    /// Event log rendered at the bottom of the diagnostic screen.
    let log = DiagnosticLog(category: "ble")

    /// Persistent capture of every notification, for offline analysis.
    let recorder = PacketRecorder()

    /// Reassembles the fragmented 669A9101 stream. Read-only: it consumes fragments and
    /// produces messages, and has no path back to the pump.
    private let fragmentAssembler = MedtrumFrameAssembler()

    // MARK: - private state

    private var centralManager: CBCentralManager?

    /// The pump we are talking to, retained so reconnects and restoration can find it again.
    private var pumpPeripheral: CBPeripheral?

    /// The CGM characteristic, retained so a recycle can unsubscribe explicitly.
    private var cgmCharacteristic: CBCharacteristic?

    /// Bounded backoff, matching upstream. EasyPatch owns the session; do not hammer it.
    private var reconnectPolicy = ReconnectPolicy()

    /// Health of the 669A9141 glucose stream: watchdog, duplicates and backfill.
    private var streamTracker = CGMStreamTracker()

    /// When we last subscribed, so the watchdog has a reference before the first packet.
    private var subscribedAt: Date?

    /// Generation counters let a newly armed timer invalidate the previous one without
    /// holding Timer objects; a stale fire simply finds a mismatched generation.
    private var watchdogGeneration = 0
    private var reconnectGeneration = 0

    /// True while a recycle is in flight, so a disconnect we caused does not schedule a
    /// second reconnect on top of the one already pending.
    private var isRecycling = false

    /// Key under which the pump's identifier is persisted, so reconnects and relaunches
    /// can go straight to the known peripheral instead of scanning — which upstream
    /// MedtrumKit notes is "the only thing that works while backgrounded".
    private static let peripheralIdentifierKey = "medtrum.peripheralIdentifier"

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

        // Discovery starts over for this session.
        characteristics.removeAll()

        // When EasyPatch already holds the link, iOS hands us a peripheral that is
        // *already* connected. CoreBluetooth does not reliably deliver another didConnect
        // in that case, so drive setup directly — this is what the upstream xDrip base
        // class does in stopScanAndconnect, and it removes one variable from the diagnosis.
        if peripheral.state == .connected {
            log.info("Peripheral \(peripheral.name ?? "unnamed") is already connected, going straight to service discovery")
            centralManager(central, didConnect: peripheral)
            return
        }

        log.info("Connecting to \(peripheral.name ?? "unnamed") \(peripheral.identifier.uuidString)")

        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    private func scheduleReconnect(reason: ReconnectReason) {
        guard let central = centralManager else { return }

        let delay = reconnectPolicy.nextDelay()
        reconnectGeneration += 1
        let generation = reconnectGeneration

        lastReconnectReason = reason
        lastReconnectAt = Date()
        log.info("Reconnect #\(reconnectPolicy.attempt) in \(Int(delay))s — \(reason.rawValue)")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reconnectGeneration == generation else { return }
            guard central.state == .poweredOn else {
                self.log.warning("Reconnect skipped: Bluetooth is \(central.state.displayName)")
                return
            }

            self.isRecycling = false
            self.reconnectCount += 1

            // Prefer the exact peripheral we know. Scanning is the last resort, and it is
            // useless in the background — the pump is not advertising while EasyPatch
            // holds the link.
            if let peripheral = self.knownPeripheral(using: central) {
                self.connect(to: peripheral, using: central)
            } else {
                self.log.warning("Known peripheral unavailable, falling back to discovery")
                self.findPump(using: central)
            }
        }
    }

    /// The pump we already know about: the retained reference if we still hold one,
    /// otherwise looked up by the identifier we persisted.
    private func knownPeripheral(using central: CBCentralManager) -> CBPeripheral? {
        if let peripheral = pumpPeripheral {
            return peripheral
        }

        guard let stored = UserDefaults.standard.string(forKey: Self.peripheralIdentifierKey),
              let identifier = UUID(uuidString: stored) else { return nil }

        let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first
        if peripheral != nil {
            log.info("Recovered known peripheral \(stored) by identifier")
        }
        return peripheral
    }

    // MARK: - CGM stream watchdog

    /// Arms the inactivity watchdog. A healthy sensor notifies every two minutes; upstream
    /// allows seven before deciding an apparently connected session is stale.
    ///
    /// This is the mechanism MedProbe was missing. Previously, when 669A9141 stopped
    /// delivering while the link stayed up, nothing noticed and nothing recovered.
    private func armCGMWatchdog() {
        watchdogGeneration += 1
        let generation = watchdogGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + CGMStreamTracker.inactivityTimeout) { [weak self] in
            guard let self, self.watchdogGeneration == generation else { return }
            self.checkCGMStreamHealth()
        }
    }

    private func cancelCGMWatchdog() {
        watchdogGeneration += 1
    }

    private func checkCGMStreamHealth() {
        guard let peripheral = pumpPeripheral, peripheral.state == .connected else { return }
        guard let since = subscribedAt else { return }

        guard streamTracker.isStale(now: Date(), since: since) else {
            armCGMWatchdog()
            return
        }

        let age = streamTracker.packetAge(now: Date()).map { Int($0 / 60) }
        log.error("No valid CGM packet for \(Int(CGMStreamTracker.inactivityTimeout / 60))+ min (last: \(age.map { "\($0) min ago" } ?? "never")). Recycling our connection.")

        recycleConnection(reason: .cgmStreamStalled)
    }

    /// Drops and rebuilds *our* CoreBluetooth connection.
    ///
    /// This affects only MedProbe's view of the link. EasyPatch keeps its own connection;
    /// iOS reference-counts the underlying ACL link, so cancelling ours does not take the
    /// pump away from the app that owns the session.
    private func recycleConnection(reason: ReconnectReason) {
        guard let central = centralManager, let peripheral = pumpPeripheral else { return }
        guard !isRecycling else { return }

        isRecycling = true
        cancelCGMWatchdog()

        // Unsubscribe before dropping the link. If the subscription itself went stale,
        // tearing it down explicitly is the part that matters.
        if let characteristic = cgmCharacteristic, characteristic.isNotifying {
            peripheral.setNotifyValue(false, for: characteristic)
        }

        connectionState = .disconnected
        central.cancelPeripheralConnection(peripheral)

        scheduleReconnect(reason: reason)
    }

    // MARK: - characteristic bookkeeping (temporary diagnostic)

    /// Adds a characteristic if we have not seen it, keeping any counts already collected.
    private func record(_ entry: DiagnosticCharacteristic) {
        guard !characteristics.contains(where: { $0.id == entry.id }) else { return }
        characteristics.append(entry)
        characteristics.sort { $0.id < $1.id }
    }

    /// Mutates one recorded characteristic in place, matching on service + characteristic UUID.
    private func update(uuid: String,
                        service: String,
                        _ mutate: (inout DiagnosticCharacteristic) -> Void) {
        // A notification can in principle arrive before discovery bookkeeping, and the
        // service UUID may be unavailable; match on the characteristic alone in that case
        // rather than losing the packet from the counts.
        let index = characteristics.firstIndex { $0.uuid == uuid && $0.serviceUUID == service }
            ?? characteristics.firstIndex { $0.uuid == uuid }

        if let index {
            mutate(&characteristics[index])
        } else {
            var entry = DiagnosticCharacteristic(serviceUUID: service, uuid: uuid, propertiesRaw: 0)
            mutate(&entry)
            characteristics.append(entry)
            characteristics.sort { $0.id < $1.id }
        }
    }

    // MARK: - packet handling

    private func handleNotification(_ data: Data) {
        // Counting and hex logging already happened in didUpdateValueFor, before filtering.
        switch MedtrumPacketDecoder.decode(data) {
        case .success(let reading):
            lastReading = reading
            lastRejectedPacketHex = nil
            lastRejectionReason = nil

            // A valid packet is the only thing that proves the session works. Reset the
            // backoff here, not on didConnect: connecting and then receiving nothing is
            // precisely the failure being recovered from.
            reconnectPolicy.reset()

            let update = streamTracker.accept(reading)
            lastValidCGMPacketAt = streamTracker.lastValidPacketAt
            armCGMWatchdog()

            if update.isDuplicate {
                log.info("Duplicate counter \(reading.counter), ignored")
                return
            }

            cgmReadingCount = streamTracker.deliveredCount
            backfilledReadingCount = streamTracker.backfilledCount
            missedCycleCount = streamTracker.missedCycleCount

            log.info(String(format: "Glucose decoded %.1f mg/dL (%.1f mmol/L) raw=%d cal=%d counter=%d",
                            reading.mgdl, reading.mmoll,
                            Int(reading.rawGlucose), Int(reading.calibrationFactor), reading.counter))

            if update.missedCycles > 0 {
                log.warning("Gap of \(update.missedCycles) cycle(s); recovered \(update.backfilled.count) from history")
                for recovered in update.backfilled {
                    log.info(String(format: "Backfilled %.1f mmol/L (counter=%d, %@)",
                                    recovered.mmoll, recovered.counter,
                                    Self.timeFormatter.string(from: recovered.timestamp)))
                    recorder.record(characteristic: "CGM-BACKFILL",
                                    data: Data(),
                                    at: recovered.timestamp)
                }
                lastBackfilled = update.backfilled
            }

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
        pumpPeripheral = peripheral
        peripheral.delegate = self

        // Only identifiers that actually produced a connection are stored, and the value
        // survives relaunch, so scanning is only ever needed the first time.
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.peripheralIdentifierKey)

        log.info("Connected to \(peripheral.name ?? "unnamed"), discovering services")

        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        log.error("Failed to connect: \(error?.localizedDescription ?? "no error given")")
        scheduleReconnect(reason: .connectFailed)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        isCGMCharacteristicNotifying = false
        cgmCharacteristic = nil
        cancelCGMWatchdog()

        log.warning("Disconnected: \(error?.localizedDescription ?? "clean disconnect")")

        // A disconnect we initiated already has a reconnect scheduled; adding another here
        // would run two ladders at once.
        guard !isRecycling else { return }

        scheduleReconnect(reason: .disconnected)
    }
}

// MARK: - CBPeripheralDelegate

extension MedtrumBluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log.error("Service discovery failed: \(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        log.info("Discovered \(services.count) service(s)")

        if !services.contains(where: { $0.uuid == Self.serviceUUID }) {
            log.warning("Medtrum service \(Self.serviceUUID.uuidString) not among discovered services")
        }

        for service in services {
            log.info("Service \(service.uuid.uuidString), discovering all characteristics")
            // TEMPORARY DIAGNOSTIC: nil, not a filtered list.
            //
            // The upstream xDrip base class also discovers with nil, and MedProbe previously
            // asked for 669A9141 alone. A filtered discovery is the one thing our setup did
            // differently from the implementation that demonstrably receives glucose, so it
            // has to be ruled out — and it is the only way to see what else the pump exposes.
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            log.error("Characteristic discovery failed for \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        let found = service.characteristics ?? []
        log.info("Service \(service.uuid.uuidString) has \(found.count) characteristic(s)")

        for characteristic in found {
            let raw = UInt(characteristic.properties.rawValue)
            let entry = DiagnosticCharacteristic(
                serviceUUID: service.uuid.uuidString,
                uuid: characteristic.uuid.uuidString,
                propertiesRaw: raw
            )
            record(entry)

            log.info("Characteristic \(characteristic.uuid.uuidString) properties \(raw) [\(entry.propertiesDescription)] isNotifying=\(characteristic.isNotifying)")

            guard entry.supportsNotifications else {
                log.info("Not subscribing to \(entry.shortUUID): no notify or indicate property")
                continue
            }

            // Production mode listens to the glucose characteristic alone, keeping the BLE
            // footprint to what MedProbe actually needs. Diagnostic mode subscribes to
            // everything that can push data, which is how 9101 and 9120 were mapped in the
            // first place. Subscribing is read-only either way: it enables a notification,
            // it does not send the pump a command.
            let diagnosticMode = MedProbeConstants.isDiagnosticModeEnabled
            if !diagnosticMode && characteristic.uuid != Self.cgmNotifyCharacteristicUUID {
                log.info("Not subscribing to \(entry.shortUUID): production mode listens to CGM only")
                continue
            }

            if characteristic.uuid == Self.cgmNotifyCharacteristicUUID {
                cgmCharacteristic = characteristic
            }

            update(uuid: entry.uuid, service: entry.serviceUUID) { $0.subscribeAttempted = true }
            log.info("Subscribing to \(entry.shortUUID)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
        let shortUUID = String(characteristic.uuid.uuidString.prefix(8))

        if let error {
            log.error("Subscribe failed on \(shortUUID): \(error.localizedDescription)")
            update(uuid: characteristic.uuid.uuidString, service: serviceUUID) {
                $0.subscribeError = error.localizedDescription
                $0.isNotifying = false
            }
            return
        }

        update(uuid: characteristic.uuid.uuidString, service: serviceUUID) {
            $0.isNotifying = characteristic.isNotifying
            $0.subscribeError = nil
        }

        if characteristic.uuid == Self.cgmNotifyCharacteristicUUID {
            isCGMCharacteristicNotifying = characteristic.isNotifying

            if characteristic.isNotifying {
                // The watchdog measures from here, so a session that subscribes and then
                // never delivers is caught just like one that stops mid-stream.
                subscribedAt = Date()
                armCGMWatchdog()
                log.info("CGM watchdog armed: \(Int(CGMStreamTracker.inactivityTimeout / 60)) min")
            } else {
                cancelCGMWatchdog()
            }
        }

        if characteristic.isNotifying {
            connectionState = .subscribed
            log.info("Notifications enabled on \(shortUUID)")
        } else {
            log.warning("Notifications disabled on \(shortUUID)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        let uuid = characteristic.uuid.uuidString
        let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
        let shortUUID = String(uuid.prefix(8))

        if let error {
            log.error("Notification error on \(shortUUID): \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else {
            log.warning("Notification on \(shortUUID) carried no value")
            return
        }

        // TEMPORARY DIAGNOSTIC: log and count every notification BEFORE any UUID filtering,
        // so a packet arriving on an unexpected characteristic cannot be silently dropped —
        // which is exactly the failure we are chasing.
        let hex = MedtrumPacketDecoder.hexString(value)
        packetsReceived += 1

        // Persist before anything else can filter or interpret the packet.
        recorder.record(characteristic: uuid, data: value)

        update(uuid: uuid, service: serviceUUID) {
            $0.packetCount += 1
            $0.lastPacketHex = hex
            $0.lastPacketAt = Date()
        }
        log.info("NOTIFY \(shortUUID) len=\(value.count) hex=\(hex)")

        switch characteristic.uuid {
        case Self.cgmNotifyCharacteristicUUID:
            handleNotification(value)

        case Self.notificationCharacteristicUUID:
            handleFieldMaskNotification(value)

        case Self.fragmentStreamCharacteristicUUID:
            handleFragment(value)

        default:
            log.info("No parser for \(shortUUID); packet recorded only")
        }
    }

    // MARK: - AndroidAPS-derived parsing

    /// Parses a 669A9120 field-mask notification. Reports what the pump said; sends nothing.
    private func handleFieldMaskNotification(_ data: Data) {
        switch MedtrumNotificationParser.parse(data) {
        case .success(let notification):
            lastNotification = notification

            if let units = notification.reservoirUnits {
                reservoirUnits = units
                reservoirUpdatedAt = Date()
            }

            if let state = notification.cgmStateByte, state != cgmStateByte {
                let previous = cgmStateByte
                cgmStateByte = state
                cgmStateChangedAt = Date()
                log.warning(String(format: "CGM state byte %@ -> 0x%02X",
                                   previous.map { String(format: "0x%02X", $0) } ?? "none",
                                   state))
            }

            // Therapy fields are withheld from the standard log. The count is still
            // reported, so the log never implies the packet carried less than it did.
            let diagnosticMode = MedProbeConstants.isDiagnosticModeEnabled
            let visible = diagnosticMode ? notification.fields : notification.nonTherapyFields

            var summary = visible
                .map { field -> String in
                    if let interpretation = field.interpretation {
                        return "\(field.name): \(interpretation)"
                    }
                    return "\(field.name)=\(field.hex)"
                }
                .joined(separator: ", ")

            let withheld = notification.withheldTherapyFieldCount
            if !diagnosticMode && withheld > 0 {
                summary += summary.isEmpty ? "" : ", "
                summary += "\(withheld) therapy field(s) withheld"
            }

            log.info(String(format: "9120 state=0x%02X mask=0x%04X %@",
                            notification.stateRaw, notification.fieldMask, summary))

        case .failure(let error):
            log.warning("9120 parse failed: \(String(describing: error))")
        }
    }

    /// Feeds a 669A9101 fragment to the reassembler. Purely passive: we are watching
    /// replies to commands EasyPatch sent, and never provoke one ourselves.
    private func handleFragment(_ data: Data) {
        switch fragmentAssembler.accept(data) {
        case .accumulating(let fragmentCount, let have, let need):
            log.info("9101 fragment \(fragmentCount) accumulating, \(have)/\(need) bytes")

        case .completed(let frame):
            lastAssembledFrame = frame
            assembledFrameCount += 1
            log.info("9101 message reassembled: \(frame.fragmentCount) fragments, \(frame.payload.count) bytes, checksums \(frame.isIntact ? "valid" : "INVALID")")
            // The reassembled payload is deliberately not interpreted.
            recorder.record(characteristic: "9101-ASSEMBLED", data: Data(frame.payload))

        case .discarded(let reason):
            log.warning("9101 fragment discarded: \(reason)")
        }
    }
}

extension MedtrumBluetoothManager {

    /// Short time format used in log lines about backfilled readings.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
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
