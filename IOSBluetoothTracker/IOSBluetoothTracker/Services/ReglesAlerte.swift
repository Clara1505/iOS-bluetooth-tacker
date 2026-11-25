//
//  ReglesAlerte.swift
//  IOSBluetoothTracker
//

import Foundation

/// Règles pures qui attribuent un niveau d'alerte aux appareils d'un balayage complet (IOS-5).
///
/// Portée MVP (décision du 25/11) : évaluation sur un seul balayage.
/// La comparaison entre balayages (même inconnu vu sur 2 balayages) relève d'IOS-6.
enum ReglesAlerte {
    /// Signal à partir duquel un appareil est considéré comme proche, en dBm.
    /// Proposition à valider avec un vrai traceur (hypothèse : environ 1 à 2 m, non mesuré).
    static let rssiProche = -60
    /// Durée minimale entre la première et la dernière détection pour considérer
    /// qu'un appareil est resté là pendant le balayage, en secondes (sur un balayage de 30 s).
    /// Proposition à valider avec un vrai traceur.
    static let dureePresenceMinimale: TimeInterval = 20

    /// Niveau d'un appareil.
    /// - Parameters:
    ///   - appareil: appareil vu pendant un balayage complet.
    ///   - estDeConfiance: `true` si l'appareil est dans la liste de confiance.
    /// - Returns: `nil` pour un appareil de confiance ; `.alerte` pour un inconnu proche
    ///   et présent au moins `dureePresenceMinimale` ; `.info` pour tout autre inconnu.
    static func niveau(pour appareil: AppareilDetecte, estDeConfiance: Bool) -> NiveauAlerte? {
        guard !estDeConfiance else { return nil }
        let estProche = appareil.rssi >= rssiProche
        let dureePresence = appareil.derniereDetection.timeIntervalSince(appareil.premiereDetection)
        let estReste = dureePresence >= dureePresenceMinimale
        return estProche && estReste ? .alerte : .info
    }

    /// Évalue tous les appareils d'un balayage.
    /// - Parameters:
    ///   - appareils: appareils d'un balayage `.complet`. Ne jamais appeler pour un
    ///     contrôle impossible : il n'entre pas dans les règles d'alerte (ARCH-4 §2, D4).
    ///   - estDeConfiance: indique si un appareil est dans la liste de confiance.
    /// - Returns: les appareils évalués, du plus grave au moins grave, puis du signal le plus fort
    ///   au plus faible ; les appareils de confiance en dernier.
    static func evaluer(
        _ appareils: [AppareilDetecte],
        estDeConfiance: (AppareilDetecte) -> Bool
    ) -> [AppareilEvalue] {
        appareils
            .map { AppareilEvalue(appareil: $0, niveau: niveau(pour: $0, estDeConfiance: estDeConfiance($0))) }
            .sorted { gauche, droite in
                // `nil` (confiance) passe après tous les niveaux : on le compare comme -1.
                let rangGauche = gauche.niveau?.rawValue ?? -1
                let rangDroite = droite.niveau?.rawValue ?? -1
                if rangGauche != rangDroite { return rangGauche > rangDroite }
                return gauche.appareil.rssi > droite.appareil.rssi
            }
    }

    /// Niveau le plus élevé parmi les appareils évalués (« le plus élevé l'emporte »).
    /// - Parameter evaluations: appareils évalués.
    /// - Returns: le niveau maximal, ou `nil` s'il n'y a aucun appareil inconnu.
    static func niveauGlobal(_ evaluations: [AppareilEvalue]) -> NiveauAlerte? {
        evaluations.compactMap(\.niveau).max()
    }
}
