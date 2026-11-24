import Foundation
import Observation

@MainActor
@Observable
final class BalayageVueModele {
    private(set) var resultat: ResultatBalayage?
    private(set) var enCours = false
    private let service: any ServiceBalayage

    init(service: any ServiceBalayage) {
        self.service = service
    }

    /// Lance un contrôle de sécurité et publie son résultat.
    func lancerControle() async {
        guard !enCours else { return }
        enCours = true
        resultat = await service.lancerBalayage(duree: ReglesBalayage.dureeParDefaut)
        enCours = false
    }
}