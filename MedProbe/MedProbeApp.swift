//
//  MedProbeApp.swift
//  MedProbe
//
//  Passive Medtrum CGM diagnostic reader. Listens only — see README.
//

import SwiftUI
import UIKit

/// Owns the BLE manager for the lifetime of the process.
///
/// CoreBluetooth state restoration requires the central manager to exist very early in launch,
/// so it is created from the app delegate rather than lazily from a view.
final class AppDelegate: NSObject, UIApplicationDelegate {

    let bluetoothManager = MedtrumBluetoothManager()

    /// Keychain-backed LibreLinkUp credentials. Never in UserDefaults or the log.
    let credentials = LibreCredentials(store: KeychainSecretStore())

    /// Replace with the Connect IQ implementation once ConnectIQ.xcframework is added to
    /// the project — see GarminTransport.swift. Everything else stays as it is.
    let transport: GarminTransport = UnavailableGarminTransport()

    private(set) lazy var libreSource = LibreLinkUpSource(
        api: LibreLinkUpAPI(),
        credentials: credentials,
        log: bluetoothManager.log
    )

    private(set) lazy var heartbeat = LibreHeartbeatListener(log: bluetoothManager.log)

    private(set) lazy var coordinator = GlucoseCoordinator(
        medtrum: MedtrumSource(manager: bluetoothManager),
        libre: libreSource,
        transport: transport,
        heartbeat: heartbeat,
        log: bluetoothManager.log
    )

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The BLE manager still starts here directly: CoreBluetooth state restoration
        // needs the central manager to exist early in launch, and the Medtrum path must
        // behave exactly as it did before the coordinator existed.
        bluetoothManager.start()
        coordinator.start()
        return true
    }
}

@main
struct MedProbeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(bluetoothManager: appDelegate.bluetoothManager)
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }

                SettingsView(coordinator: appDelegate.coordinator,
                             credentials: appDelegate.credentials)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
