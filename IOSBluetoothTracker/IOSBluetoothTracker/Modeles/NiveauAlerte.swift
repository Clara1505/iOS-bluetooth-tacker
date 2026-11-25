//
//  NiveauAlerte.swift
//  IOSBluetoothTracker
//

import Foundation

/// Niveau d'avertissement d'un appareil inconnu (ARCH-4).
///
/// MVP : `info` et `alerte` seulement. Le niveau `critique` (P2) sera ajouté après le spike ARCH-6.
/// `Comparable` : l'ordre des cas va du moins grave au plus grave, pour appliquer
/// la règle « le niveau le plus élevé l'emporte ».
enum NiveauAlerte: Int, Comparable, Sendable {
    /// Appareil inconnu, sans signe de suivi.
    case info
    /// Appareil inconnu resté proche pendant tout le balayage.
    case alerte

    static func < (gauche: NiveauAlerte, droite: NiveauAlerte) -> Bool {
        gauche.rawValue < droite.rawValue
    }
}

/// Appareil détecté accompagné de son évaluation.
struct AppareilEvalue: Identifiable, Equatable, Sendable {
    let appareil: AppareilDetecte
    /// Niveau d'avertissement, ou `nil` si l'appareil est dans la liste de confiance
    /// (un appareil de confiance ne déclenche jamais d'alerte, ARCH-4 §3).
    let niveau: NiveauAlerte?

    var id: UUID { appareil.id }
}
