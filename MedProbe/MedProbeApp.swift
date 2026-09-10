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

    /// Picks the real Connect IQ transport when the framework is part of the build, and a
    /// stand-in otherwise. Adding ConnectIQ.xcframework needs no change here.
    private(set) lazy var transport: GarminTransport = GarminTransportFactory.make(log: bluetoothManager.log)

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
            RootView(appDelegate: appDelegate)
            // Garmin Connect hands control back through the medprobe:// scheme after the
            // user picks their watches. Without this the selection completes on their
            // side and never reaches us, so no watch ever appears.
            .onOpenURL { url in
                appDelegate.coordinator.handleGarminReturn(from: url)
            }
        }
    }
}

/// Chooses what the app leads with.
///
/// Glucose first. Diagnostics is still reachable — it is how every problem so far has
/// been found — but it is a tool, not the front page, so it appears only when switched on
/// in settings.
struct RootView: View {

    let appDelegate: AppDelegate

    @AppStorage(MedProbeConstants.showDiagnosticsKey) private var showDiagnostics = false

    var body: some View {
        TabView {
            GlucoseView(coordinator: appDelegate.coordinator)
                .tabItem { Label("Glucose", systemImage: "drop.fill") }

            SettingsView(coordinator: appDelegate.coordinator,
                         credentials: appDelegate.credentials)
                .tabItem { Label("Settings", systemImage: "gearshape") }

            if showDiagnostics {
                ContentView(bluetoothManager: appDelegate.bluetoothManager)
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }
        }
        // Garmin Connect hands control back through the medprobe:// scheme after the user
        // picks their watches. Without this the selection completes on their side and
        // never reaches us, so no watch ever appears.
        .onOpenURL { url in
            appDelegate.coordinator.handleGarminReturn(from: url)
        }
    }
}
