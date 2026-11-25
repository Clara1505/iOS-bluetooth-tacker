//
//  BalayageVueModele.swift
//  IOSBluetoothTracker
//

import Foundation
import Observation

/// Vue-modèle de l'écran de contrôle de sécurité.
@MainActor
@Observable
final class BalayageVueModele {
    /// Résultat du dernier contrôle, ou `nil` si aucun contrôle n'a encore été lancé.
    private(set) var resultat: ResultatBalayage?
    /// `true` pendant un balayage, pour désactiver le bouton.
    private(set) var enCours = false
    private let service: any ServiceBalayage

    /// - Parameter service: service de balayage (vrai ou faux pour les tests).
    init(service: any ServiceBalayage) {
        self.service = service
    }

    /// Lance un contrôle de sécurité et publie son résultat.
    /// Ignoré si un contrôle est déjà en cours.
    func lancerControle() async {
        guard !enCours else { return }
        enCours = true
        resultat = await service.lancerBalayage(duree: ReglesBalayage.dureeParDefaut)
        enCours = false
    }
}
