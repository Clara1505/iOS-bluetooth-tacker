//
//  ReglesBalayage.swift
//  IOSBluetoothTracker
//

import Foundation

/// Règles pures du balayage, sans CoreBluetooth, pour pouvoir les tester facilement.
enum ReglesBalayage {
    /// Durée d'un contrôle de sécurité, en secondes.
    static let dureeParDefaut: TimeInterval = 30
    /// Plus petite valeur RSSI acceptée, en dBm.
    static let rssiMinimum = -127
    /// Longueur maximale d'un nom annoncé, en caractères (T5).
    static let longueurNomMaximale = 64

    /// Indique pourquoi le contrôle est impossible dans l'état Bluetooth donné (D4).
    /// - Parameter etat: état du Bluetooth de l'iPhone.
    /// - Returns: la raison de l'échec, ou `nil` si le balayage peut démarrer.
    ///   Un état inconnu donne `.interrompu` : en cas de doute, on ne balaye pas.
    static func raisonEchec(pour etat: EtatBluetooth) -> RaisonEchec? {
        switch etat {
        case .allume: return nil
        case .eteint: return .bluetoothCoupe
        case .nonAutorise: return .permissionRefusee
        case .nonSupporte: return .nonSupporte
        case .inconnu: return .interrompu
        }
    }

    /// Indique si une valeur RSSI est exploitable.
    /// - Parameter rssi: valeur reçue de CoreBluetooth (iOS renvoie 127 quand elle est indisponible).
    /// - Returns: `true` si la valeur est entre -127 et 0 dBm.
    static func rssiValide(_ rssi: Int) -> Bool {
        (rssiMinimum...0).contains(rssi)
    }

    /// Nettoie un nom annoncé par un appareil Bluetooth, donnée externe non fiable (T5).
    ///
    /// Étapes : retirer les caractères de contrôle (retours à la ligne, caractères invisibles
    /// qui pourraient fausser l'affichage), retirer les espaces aux extrémités, puis couper à 64 caractères.
    /// - Parameter nom: nom brut reçu, ou `nil`.
    /// - Returns: le nom nettoyé, ou `nil` s'il est absent ou vide après nettoyage.
    static func nettoyerNom(_ nom: String?) -> String? {
        guard let nom else { return nil }
        let sansControle = String(String.UnicodeScalarView(
            nom.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        let nettoye = sansControle.trimmingCharacters(in: .whitespaces)
        guard !nettoye.isEmpty else { return nil }
        return String(nettoye.prefix(longueurNomMaximale))
    }
}
