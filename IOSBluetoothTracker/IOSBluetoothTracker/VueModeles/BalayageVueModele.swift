//
//  BalayageVueModele.swift
//  IOSBluetoothTracker
//

import Foundation

/// Vue-modèle de l'écran de contrôle de sécurité.
///
/// `ObservableObject` et non `@Observable` : la macro `@Observable` demande iOS 17,
/// alors que la cible minimale du projet est iOS 15 (PM-11).
@MainActor
final class BalayageVueModele: ObservableObject {
    /// Résultat du dernier contrôle, ou `nil` si aucun contrôle n'a encore été lancé.
    @Published private(set) var resultat: ResultatBalayage?
    /// Appareils du dernier contrôle complet, avec leur niveau d'alerte.
    /// Vide si le contrôle a été impossible (D4 : pas d'évaluation sans balayage complet).
    @Published private(set) var evaluations: [AppareilEvalue] = []
    /// `true` pendant un balayage, pour désactiver le bouton.
    @Published private(set) var enCours = false
    private let service: any ServiceBalayage
    /// Vérificateur de la liste de confiance, ou `nil` tant que la liste n'est pas disponible.
    private let verificateur: VerificateurConfiance?

    /// - Parameters:
    ///   - service: service de balayage (vrai ou faux pour les tests).
    ///   - verificateur: vérificateur de la liste de confiance (TRU-1, TRU-2).
    ///     `nil` par défaut : aucun appareil n'est alors de confiance et tout appareil est
    ///     traité comme inconnu, ce qui est le choix prudent (échec en sécurité).
    init(service: any ServiceBalayage, verificateur: VerificateurConfiance? = nil) {
        self.service = service
        self.verificateur = verificateur
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
            // La liste est relue à chaque contrôle, une seule fois, pour tenir compte des appareils
            // ajoutés ou retirés depuis le contrôle précédent. Liste illisible : ensemble vide,
            // donc tout appareil reste inconnu (VerificateurConfiance, échec en sécurité).
            let idsDeConfiance = verificateur?.idsDeConfiance() ?? []
            evaluations = ReglesAlerte.evaluer(appareils) { appareil in
                self.verificateur?.estDeConfiance(appareil, parmi: idsDeConfiance) ?? false
            }
        case .controleImpossible:
            evaluations = []
        }
        enCours = false
    }
}
