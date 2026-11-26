//
//  Attente.swift
//  IOSBluetoothTracker
//

import Foundation

/// Attente asynchrone compatible iOS 15.
///
/// `Task.sleep(for: .seconds(_:))` demande iOS 16 ; seule la version en nanosecondes
/// existe sur iOS 15 (cible minimale du projet, PM-11).
enum Attente {
    /// Durée maximale acceptée, en secondes. Évite un dépassement lors de la conversion en
    /// nanosecondes et une attente démesurée si la valeur est aberrante.
    static let dureeMaximale: TimeInterval = 3_600

    /// Convertit une durée en secondes en nanosecondes, en bornant les valeurs extrêmes.
    /// - Parameter secondes: durée demandée.
    /// - Returns: nanosecondes entre 0 et `dureeMaximale`. Une durée négative ou non numérique (NaN)
    ///   donne 0 ; une durée trop grande est ramenée à `dureeMaximale`.
    static func nanosecondes(pour secondes: TimeInterval) -> UInt64 {
        // NaN n'est ni inférieur ni supérieur à rien : on le traite à part.
        guard !secondes.isNaN, secondes > 0 else { return 0 }
        let borne = min(secondes, dureeMaximale)
        return UInt64(borne * 1_000_000_000)
    }

    /// Attend la durée demandée.
    /// - Parameter secondes: durée en secondes (bornée, voir `nanosecondes(pour:)`).
    /// - Throws: `CancellationError` si la tâche est annulée pendant l'attente.
    static func dormir(secondes: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: nanosecondes(pour: secondes))
    }
}
