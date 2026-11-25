import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Stockage en mémoire pour les tests.
private final class StockageEnMemoire: StockageListeDeConfiance {
    var erreurModifier: Error?
    var erreurLire: Error?
    private(set) var appelsModifier = 0
    private(set) var contenu = ContenuListe()

    func lire() throws -> ContenuListe {
        if let erreurLire { throw erreurLire }
        return contenu
    }

    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {
        appelsModifier += 1
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

/// Hacheur fictif : pas de crypto dans ces tests.
private struct HacheurFictif: HacheurIdentifiant {
    func hacher(_ identifiant: UUID) -> Data {
        Data(identifiant.uuidString.utf8)
    }
}

private func unAppareil() -> AppareilDetecte {
    AppareilDetecte(
        identifiantSysteme: UUID(),
        nomAnnonce: nil,
        rssi: -55,
        premiereDetection: Date(timeIntervalSince1970: 1_800_000_000),
        derniereDetection: Date(timeIntervalSince1970: 1_800_000_030)
    )
}

@MainActor
@Suite("Enrôlement des appareils de confiance (TRU-1)")
struct EnrolementTests {

    private func fabriquer(_ stockage: StockageEnMemoire) -> EnrolementVueModele {
        EnrolementVueModele(
            modificateur: ModificateurListeDeConfiance(stockage: stockage),
            hacheur: HacheurFictif(),
            mode: { .faceID },
            maintenant: { Date(timeIntervalSince1970: 1_800_000_100) }
        )
    }

    @Test("Un nom valide ajoute l'appareil sous son identifiant haché")
    func enrolementReussi() {
        let stockage = StockageEnMemoire()
        let vueModele = fabriquer(stockage)
        let appareil = unAppareil()
        vueModele.nomSaisi = "Sac 2 Bleu"

        vueModele.enroler(appareil)

        #expect(vueModele.etat == .termine)
        #expect(vueModele.nomSaisi.isEmpty)
        #expect(stockage.contenu.appareils.count == 1)
        #expect(stockage.contenu.appareils.first?.nom == "Sac 2 Bleu")
        #expect(stockage.contenu.appareils.first?.idHache == Data(appareil.identifiantSysteme.uuidString.utf8))
    }

    @Test("Un nom invalide est refusé sans toucher au stockage")
    func nomInvalide() {
        let stockage = StockageEnMemoire()
        let vueModele = fabriquer(stockage)
        vueModele.nomSaisi = "Été"

        vueModele.enroler(unAppareil())

        #expect(vueModele.etat == .nomInvalide(.caractereNonAutorise))
        #expect(stockage.appelsModifier == 0)
    }

    @Test("Une authentification refusée n'ajoute rien")
    func authentificationRefusee() {
        let stockage = StockageEnMemoire()
        stockage.erreurModifier = ErreurListeDeConfiance.authentificationEchouee
        let vueModele = fabriquer(stockage)
        vueModele.nomSaisi = "Sac"

        vueModele.enroler(unAppareil())

        #expect(vueModele.etat == .authentificationRefusee)
        #expect(stockage.contenu.appareils.isEmpty)
    }

    @Test("Une erreur système est signalée")
    func erreurSysteme() {
        let stockage = StockageEnMemoire()
        stockage.erreurModifier = ErreurListeDeConfiance.erreurSysteme
        let vueModele = fabriquer(stockage)
        vueModele.nomSaisi = "Sac"

        vueModele.enroler(unAppareil())

        #expect(vueModele.etat == .erreur)
    }

    @Test("Un appareil enrôlé est reconnu comme de confiance")
    func verificateurReconnaitUnAppareil() {
        let stockage = StockageEnMemoire()
        let vueModele = fabriquer(stockage)
        let appareil = unAppareil()
        vueModele.nomSaisi = "Sac"
        vueModele.enroler(appareil)
        let verificateur = VerificateurConfiance(stockage: stockage, hacheur: HacheurFictif())

        let ids = verificateur.idsDeConfiance()

        #expect(verificateur.estDeConfiance(appareil, parmi: ids))
        #expect(verificateur.estDeConfiance(unAppareil(), parmi: ids) == false)
    }

    @Test("Liste illisible : aucun appareil n'est de confiance")
    func listeIlisibleEstPrudente() {
        let stockage = StockageEnMemoire()
        stockage.erreurLire = ErreurListeDeConfiance.signatureInvalide
        let verificateur = VerificateurConfiance(stockage: stockage, hacheur: HacheurFictif())

        #expect(verificateur.idsDeConfiance().isEmpty)
    }
}