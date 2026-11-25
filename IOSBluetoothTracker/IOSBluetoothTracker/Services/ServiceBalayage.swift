//
//  ServiceBalayage.swift
//  IOSBluetoothTracker
//

import Foundation

/// Service qui lance un balayage Bluetooth.
///
/// Implémenté par le vrai service (`ServiceBalayageBluetooth`) et par un faux
/// (`FauxServiceBalayage`) pour les tests et les aperçus SwiftUI.
/// Isolé sur le thread principal, comme le vue-modèle et CoreBluetooth (file `nil` = principale).
@MainActor
protocol ServiceBalayage {
    /// Lance un balayage d'environ `duree` secondes.
    /// - Parameter duree: durée du balayage, en secondes (30 s par défaut, voir `ReglesBalayage`).
    /// - Returns: `.complet` avec les appareils vus, ou `.controleImpossible` si le Bluetooth
    ///   est indisponible ou coupé pendant le balayage. Jamais une liste vide dans ce cas (D4).
    func lancerBalayage(duree: TimeInterval) async -> ResultatBalayage
}
