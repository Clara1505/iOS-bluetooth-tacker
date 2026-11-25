//
//  CollecteurAppareils.swift
//  IOSBluetoothTracker
//

import Foundation

/// Regroupe les détections reçues pendant un balayage : une entrée par identifiant.
///
/// CoreBluetooth signale le même appareil plusieurs fois (option « doublons autorisés ») :
/// le collecteur met à jour l'entrée existante au lieu d'en créer une nouvelle.
struct CollecteurAppareils {
    private var parIdentifiant: [UUID: AppareilDetecte] = [:]

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
        parIdentifiant[identifiant] = AppareilDetecte(
            identifiantSysteme: identifiant,
            nomAnnonce: ReglesBalayage.nettoyerNom(nom) ?? existant?.nomAnnonce,
            rssi: rssiRetenu,
            premiereDetection: existant?.premiereDetection ?? date,
            derniereDetection: date
        )
    }

    /// Appareils détectés, du signal le plus fort au plus faible.
    var appareils: [AppareilDetecte] {
        parIdentifiant.values.sorted { $0.rssi > $1.rssi }
    }

    /// Oublie toutes les détections, avant un nouveau balayage.
    mutating func vider() {
        parIdentifiant.removeAll()
    }
}
