//
//  AppareilDetecte.swift
//  IOSBluetoothTracker
//
//  Created by Guest User on 24/11/2026.
//

import Foundation

/// Appareil Bluetooth vu pendant un balayage, conservé en mémoire uniquement.
struct AppareilDetecte: Identifiable, Equatable, Sendable {
    /// Identifiant fourni par iOS ; il peut changer d'un balayage à l'autre (hypothèse H1).
    let id: UUID
    let nom: String?
    let rssi: Int
    let vuLe: Date
}
