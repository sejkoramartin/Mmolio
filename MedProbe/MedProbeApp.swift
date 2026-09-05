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

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        bluetoothManager.start()
        return true
    }
}

@main
struct MedProbeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(bluetoothManager: appDelegate.bluetoothManager)
        }
    }
}
