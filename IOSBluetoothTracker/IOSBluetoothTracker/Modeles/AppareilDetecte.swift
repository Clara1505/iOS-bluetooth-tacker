//
//  AppareilDetecte.swift
//  IOSBluetoothTracker
//

import Foundation

/// Appareil Bluetooth vu pendant un balayage.
///
/// Reste en mémoire uniquement : jamais persisté, commité ni journalisé tel quel (I2, I5).
/// Le hachage de l'identifiant (HMAC-SHA256) est fait plus tard, avant tout stockage (TRU-6).
struct AppareilDetecte: Identifiable, Equatable, Sendable {
    /// Identifiant attribué par iOS (`CBPeripheral.identifier`), pas l'adresse matérielle.
    /// Il peut changer d'un balayage à l'autre (hypothèse H1, à vérifier avec l'AirTag, ARCH-6).
    let identifiantSysteme: UUID
    /// Nom annoncé, déjà nettoyé par `ReglesBalayage.nettoyerNom(_:)` (T5), ou `nil` s'il n'y en a pas.
    let nomAnnonce: String?
    /// Dernière puissance de signal valide, en dBm (entre -127 et 0).
    let rssi: Int
    /// Date de la première détection pendant ce balayage.
    let premiereDetection: Date
    /// Date de la dernière détection pendant ce balayage.
    let derniereDetection: Date

    /// Identifiant utilisé par SwiftUI pour les listes.
    var id: UUID { identifiantSysteme }
}
