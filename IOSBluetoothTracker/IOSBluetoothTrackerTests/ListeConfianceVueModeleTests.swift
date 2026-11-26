import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Stockage en mémoire pour les tests.
private final class StockageEnMemoire: StockageListeDeConfiance {
    var erreurModifier: Error?
    var erreurLire: Error?
    private(set) var contenu = ContenuListe()

    func lire() throws -> ContenuListe {
        if let erreurLire { throw erreurLire }
        return contenu
    }

    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {
        if let erreurModifier { throw erreurModifier }
        var copie = contenu
        copie.ajouterHistorique(entree)
        transformation(&copie)
        contenu = copie
    }

    func reinitialiser() throws {
        contenu = ContenuListe()
    }
}

@MainActor
@Suite("Écran de la liste de confiance (TRU-5)")
struct ListeConfianceVueModeleTests {

    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let appareil = AppareilDeConfiance(
        idHache: Data([1, 2, 3]),
        nom: "Sac",
        ajouteLe: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private func fabriquer(_ stockage: StockageEnMemoire) throws -> ListeConfianceVueModele {
        try stockage.modifier(
            entree: EntreeHistorique(date: date, action: .ajout, nomAppareil: "Sac", mode: .biometrie)
        ) { $0.appareils.append(appareil) }
        return ListeConfianceVueModele(
            stockage: stockage,
            modificateur: ModificateurListeDeConfiance(stockage: stockage),
            mode: { .biometrie },
            maintenant: { date }
        )
    }

    @Test("Le chargement affiche les appareils de la liste")
    func chargement() throws {
        let vueModele = try fabriquer(StockageEnMemoire())

        vueModele.charger()

        #expect(vueModele.contenu.appareils.count == 1)
        #expect(vueModele.listeIllisible == false)
    }

    @Test("Une liste illisible est signalée et jamais présentée comme vide")
    func listeIllisible() throws {
        let stockage = StockageEnMemoire()
        let vueModele = try fabriquer(stockage)
        stockage.erreurLire = ErreurListeDeConfiance.signatureInvalide

        vueModele.charger()

        #expect(vueModele.listeIllisible)
        #expect(vueModele.contenu.appareils.isEmpty)
    }

    @Test("Une suppression authentifiée retire l'appareil")
    func suppressionReussie() throws {
        let vueModele = try fabriquer(StockageEnMemoire())
        vueModele.charger()

        vueModele.supprimer(appareil)

        #expect(vueModele.contenu.appareils.isEmpty)
        #expect(vueModele.messageErreur == nil)
    }

    @Test("Une authentification refusée garde l'appareil et affiche un message")
    func suppressionRefusee() throws {
        let stockage = StockageEnMemoire()
        let vueModele = try fabriquer(stockage)
        vueModele.charger()
        stockage.erreurModifier = ErreurListeDeConfiance.authentificationEchouee

        vueModele.supprimer(appareil)

        #expect(vueModele.contenu.appareils.count == 1)
        #expect(vueModele.messageErreur != nil)
    }
}