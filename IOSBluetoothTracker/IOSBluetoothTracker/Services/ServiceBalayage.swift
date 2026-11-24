//
//  ServiceBalayage.swift
//  IOSBluetoothTracker
//
//  Created by Guest User on 24/11/2026.
//

import Foundation

/// Raisons pour lesquelles un contrôle ne peut pas aboutir (menace D4).
enum ErreurBalayage: Error, Equatable, Sendable {
    case bluetoothDesactive
    case permissionRefusee
    case bluetoothIndisponible
    case interrompu
}

/// Lance un balayage Bluetooth. Implémenté par le vrai service (IOS-2) et par un faux dans les tests.
protocol ServiceBalayage: Sendable {
    /// Balaye pendant `duree` et renvoie les appareils vus.
    /// - Throws: `ErreurBalayage` si le contrôle est impossible.
    ///   Un échec n'est jamais renvoyé sous forme de liste vide (D4).
    func balayer(duree: Duration) async throws -> [AppareilDetecte]
}
