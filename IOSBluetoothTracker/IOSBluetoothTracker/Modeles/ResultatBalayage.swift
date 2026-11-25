//
//  ResultatBalayage.swift
//  IOSBluetoothTracker
//

import Foundation

/// Raison pour laquelle un contrôle de sécurité n'a pas pu aller jusqu'au bout (D4).
enum RaisonEchec: Equatable, Sendable {
    /// Le Bluetooth de l'iPhone est éteint.
    case bluetoothCoupe
    /// L'utilisateur a refusé l'accès au Bluetooth.
    case permissionRefusee
    /// Le balayage a été arrêté avant la fin (Bluetooth coupé en cours, état inconnu, double lancement).
    case interrompu
    /// L'appareil ne gère pas le Bluetooth Low Energy (simulateur, par exemple).
    case nonSupporte
}

/// Résultat d'un contrôle de sécurité (champ `resultat` du modèle ARCH-3).
///
/// Règle D4 : un contrôle qui n'a pas abouti est toujours `.controleImpossible`,
/// jamais `.complet([])`. Sinon l'app afficherait « aucun appareil » alors qu'elle n'a rien vérifié.
enum ResultatBalayage: Equatable, Sendable {
    /// Le balayage s'est déroulé en entier ; la liste peut être vide.
    /// `plafondAtteint` vaut `true` si trop d'appareils ont été vus et que la liste a été limitée (D1) :
    /// l'écran doit alors afficher un avertissement.
    case complet([AppareilDetecte], plafondAtteint: Bool = false)
    /// Le balayage n'a pas pu être fait ou a été interrompu.
    case controleImpossible(RaisonEchec)
}
