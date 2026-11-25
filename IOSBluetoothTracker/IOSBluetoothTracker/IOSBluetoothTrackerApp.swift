//
//  IOSBluetoothTrackerApp.swift
//  IOSBluetoothTracker
//
//  Created by Guest User on 24/11/2026.
//

import SwiftUI

@main
struct IOSBluetoothTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            BalayageVue(service: ServiceBalayageBluetooth())
        }
    }
}
