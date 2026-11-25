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
    // Liste de confiance pas encore passée : il manque le hacheur HMAC-SHA256 (TRU-6, relu par Aida).
    // En attendant, `verificateur` vaut nil et tout appareil est traité comme inconnu (choix prudent).
    BalayageVue(service: ServiceBalayageBluetooth())
        .masquerApercuMultitache()
}
    }
}
