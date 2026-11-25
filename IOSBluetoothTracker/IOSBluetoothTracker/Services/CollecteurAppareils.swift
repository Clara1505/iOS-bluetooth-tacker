//
//  CollecteurAppareils.swift
//  IOSBluetoothTracker
//

import Foundation

/// Regroupe les détections reçues pendant un balayage : une entrée par identifiant.
///
/// - Déduplication : CoreBluetooth signale le même appareil plusieurs fois (option « doublons autorisés ») ;
///   le collecteur met à jour l'entrée existante au lieu d'en créer une nouvelle.
/// - Plafond de sécurité (D1) : au-delà de `plafond` appareils, la liste ne grandit plus,
///   pour qu'une inondation d'annonces ne ralentisse pas l'app ni ne la fasse planter.
struct CollecteurAppareils {
    private var parIdentifiant: [UUID: AppareilDetecte] = [:]
    /// Nombre maximal d'appareils gardés.
    let plafond: Int
    /// `true` dès qu'un appareil a dû être écarté ou remplacé parce que le plafond était atteint.
    private(set) var plafondAtteint = false

    /// - Parameter plafond: nombre maximal d'appareils gardés (au moins 1).
    ///   Par défaut `ReglesBalayage.plafondAppareils` ; une autre valeur sert surtout aux tests.
    init(plafond: Int = ReglesBalayage.plafondAppareils) {
        self.plafond = max(1, plafond)
    }

    /// Enregistre une détection et met à jour l'appareil s'il a déjà été vu.
    /// - Parameters:
    ///   - identifiant: identifiant attribué par iOS.
    ///   - nom: nom annoncé brut ; il est nettoyé ici (T5). Un nom absent garde le précédent.
    ///   - rssi: puissance du signal. Une valeur invalide ne fait pas disparaître l'appareil :
    ///     on garde la valeur précédente, ou le minimum à la première détection.
    ///   - date: date de la détection.
    mutating func enregistrer(identifiant: UUID, nom: String?, rssi: Int, date: Date) {
        let existant = parIdentifiant[identifiant]
        let rssiRetenu = ReglesBalayage.rssiValide(rssi)
            ? rssi
            : (existant?.rssi ?? ReglesBalayage.rssiMinimum)

        // Nouvel appareil alors que la liste est pleine : appliquer le plafond (D1).
        if existant == nil, parIdentifiant.count >= plafond {
            plafondAtteint = true
            guard faireDeLaPlace(pourRssi: rssiRetenu) else { return }
        }

        parIdentifiant[identifiant] = AppareilDetecte(
            identifiantSysteme: identifiant,
            nomAnnonce: ReglesBalayage.nettoyerNom(nom) ?? existant?.nomAnnonce,
            rssi: rssiRetenu,
            premiereDetection: existant?.premiereDetection ?? date,
            derniereDetection: date
        )
    }

    /// Retire l'appareil au signal le plus faible si le nouveau a un signal strictement plus fort.
    ///
    /// Pourquoi : un traceur qui suit l'utilisateur est en général proche, donc avec un signal fort.
    /// Un attaquant qui inonde de fausses annonces lointaines ne peut donc pas le faire sortir de la liste.
    /// Limite : des annonces fausses mais très proches (signal fort) peuvent encore remplir la liste ;
    /// c'est pourquoi le plafond atteint est signalé à l'utilisateur.
    /// - Parameter rssi: signal du nouvel appareil.
    /// - Returns: `true` si une place a été libérée, `false` si le nouvel appareil doit être ignoré.
    private mutating func faireDeLaPlace(pourRssi rssi: Int) -> Bool {
        guard let plusFaible = parIdentifiant.values.min(by: { $0.rssi < $1.rssi }),
              rssi > plusFaible.rssi else {
            return false
        }
        parIdentifiant[plusFaible.identifiantSysteme] = nil
        return true
    }

    /// Appareils détectés, du signal le plus fort au plus faible.
    /// À signal égal, ordre stable par identifiant, pour que l'affichage ne saute pas.
    var appareils: [AppareilDetecte] {
        parIdentifiant.values.sorted {
            $0.rssi != $1.rssi
                ? $0.rssi > $1.rssi
                : $0.identifiantSysteme.uuidString < $1.identifiantSysteme.uuidString
        }
    }

    /// Oublie toutes les détections et l'état du plafond, avant un nouveau balayage.
    mutating func vider() {
        parIdentifiant.removeAll()
        plafondAtteint = false
    }
}
