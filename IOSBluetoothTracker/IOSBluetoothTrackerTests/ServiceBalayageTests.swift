//
//  ServiceBalayageTests.swift
//  IOSBluetoothTrackerTests
//
//  Created by Guest User on 24/11/2026.
//

import Foundation
import Testing
@testable import IOSBluetoothTracker

struct ServiceBalayageTests {
    @Test func renvoieLesAppareilsPrevus() async throws {
        let appareil = AppareilDetecte(id: UUID(), nom: "Appareil fictif", rssi: -60, vuLe: .now)
        let service: any ServiceBalayage = FauxServiceBalayage(appareils: [appareil])
        let resultat = try await service.balayer(duree: .seconds(30))
        #expect(resultat == [appareil])
    }

    @Test func remonteLErreurQuandLeBluetoothEstCoupe() async {
        let service: any ServiceBalayage = FauxServiceBalayage(erreur: .bluetoothDesactive)
        await #expect(throws: ErreurBalayage.bluetoothDesactive) {
            try await service.balayer(duree: .seconds(30))
        }
    }
}
