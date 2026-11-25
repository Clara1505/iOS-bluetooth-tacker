//
//  FauxServiceBalayage.swift
//  IOSBluetoothTracker
//

#if DEBUG
import Foundation

/// Faux service de balayage pour les tests et les aperçus SwiftUI.
///
/// Données fictives uniquement (jamais de vrai résultat de balayage, voir CLAUDE.md section 5).
/// Placé dans la cible de l'app pour que les `#Preview` y aient accès, mais compilé
/// seulement en Debug : il n'est pas livré dans l'app finale.
struct FauxServiceBalayage: ServiceBalayage {
    /// Résultat renvoyé à chaque appel.
    let resultat: ResultatBalayage

    /// Renvoie immédiatement `resultat`, sans utiliser le Bluetooth.
    /// - Parameter duree: ignorée.
    func lancerBalayage(duree: TimeInterval) async -> ResultatBalayage {
        resultat
    }
}
#endif
