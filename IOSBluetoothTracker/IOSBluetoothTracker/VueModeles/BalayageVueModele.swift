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
    /// Appareils du dernier contrôle complet, avec leur niveau d'alerte.
    /// Vide si le contrôle a été impossible (D4 : pas d'évaluation sans balayage complet).
    private(set) var evaluations: [AppareilEvalue] = []
    /// `true` pendant un balayage, pour désactiver le bouton.
    private(set) var enCours = false
    private let service: any ServiceBalayage
    private let estDeConfiance: (AppareilDetecte) -> Bool

    /// - Parameters:
    ///   - service: service de balayage (vrai ou faux pour les tests).
    ///   - estDeConfiance: indique si un appareil est dans la liste de confiance.
    ///     Par défaut aucun appareil ne l'est : en attendant la liste (TRU-1, TRU-2),
    ///     tout appareil est traité comme inconnu, ce qui est le choix prudent.
    init(
        service: any ServiceBalayage,
        estDeConfiance: @escaping (AppareilDetecte) -> Bool = { _ in false }
    ) {
        self.service = service
        self.estDeConfiance = estDeConfiance
    }

    /// Niveau le plus élevé du dernier contrôle, ou `nil` s'il n'y a aucun appareil inconnu.
    var niveauGlobal: NiveauAlerte? {
        ReglesAlerte.niveauGlobal(evaluations)
    }

    /// Lance un contrôle de sécurité, puis publie son résultat et l'évaluation des appareils.
    /// Ignoré si un contrôle est déjà en cours.
    func lancerControle() async {
        guard !enCours else { return }
        enCours = true
        let nouveauResultat = await service.lancerBalayage(duree: ReglesBalayage.dureeParDefaut)
        resultat = nouveauResultat
        switch nouveauResultat {
        case .complet(let appareils, _):
            evaluations = ReglesAlerte.evaluer(appareils, estDeConfiance: estDeConfiance)
        case .controleImpossible:
            evaluations = []
        }
        enCours = false
    }
}
