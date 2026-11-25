import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Faux stockage : enregistre les appels et renvoie l'erreur demandée.
private final class FauxStockage: StockageListeDeConfiance {
    var erreurARenvoyer: Error?
    private(set) var appelsModifier = 0
    private(set) var contenu = ContenuListe()

    func lire() throws -> ContenuListe {
        contenu
    }

    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {
        appelsModifier += 1
        if let erreur = erreurARenvoyer {
            throw erreur
        }
        var copie = contenu
        copie.ajouterHistorique(entree)
        transformation(&copie)
        contenu = copie
    }

    func reinitialiser() throws {
        contenu = ContenuListe()
    }
}

@Suite("Modification de la liste de confiance (TRU-3)")
struct ModificateurListeTests {

    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let idHache = Data([1, 2, 3, 4])

    @Test("Une authentification échouée ne modifie rien")
    func echecAuthentificationNEcritPas() throws {
        let faux = FauxStockage()
        faux.erreurARenvoyer = ErreurListeDeConfiance.authentificationEchouee
        let modificateur = ModificateurListeDeConfiance(stockage: faux)

        let resultat = try modificateur.ajouterAppareil(
            nomBrut: "Sac",
            idHache: idHache,
            date: date,
            mode: .faceID
        )

        #expect(resultat == .echecAuthentification)
        #expect(faux.contenu.appareils.isEmpty)
    }

    @Test("Un ajout authentifié est enregistré")
    func ajoutReussi() throws {
        let faux = FauxStockage()
        let modificateur = ModificateurListeDeConfiance(stockage: faux)

        let resultat = try modificateur.ajouterAppareil(
            nomBrut: "Sac 2 Bleu",
            idHache: idHache,
            date: date,
            mode: .code
        )

        #expect(resultat == .reussie)
        #expect(faux.contenu.appareils.count == 1)
        #expect(faux.contenu.appareils.first?.nom == "Sac 2 Bleu")
    }

    @Test("Un nom invalide ne touche pas au stockage")
    func nomInvalideNAppellePasLeStockage() {
        let faux = FauxStockage()
        let modificateur = ModificateurListeDeConfiance(stockage: faux)

        #expect(throws: ErreurNomAppareil.self) {
            try modificateur.ajouterAppareil(
                nomBrut: "Été",
                idHache: idHache,
                date: date,
                mode: .faceID
            )
        }
        #expect(faux.appelsModifier == 0)
    }

    @Test("Une suppression authentifiée retire l'appareil")
    func suppressionReussie() throws {
        let faux = FauxStockage()
        let modificateur = ModificateurListeDeConfiance(stockage: faux)
        _ = try modificateur.ajouterAppareil(nomBrut: "Sac", idHache: idHache, date: date, mode: .faceID)

        let resultat = modificateur.supprimerAppareil(
            nomAppareil: "Sac",
            idHache: idHache,
            date: date,
            mode: .faceID
        )

        #expect(resultat == .reussie)
        #expect(faux.contenu.appareils.isEmpty)
    }

    @Test("Une erreur système est renvoyée telle quelle")
    func erreurSysteme() {
        let faux = FauxStockage()
        faux.erreurARenvoyer = ErreurListeDeConfiance.erreurSysteme
        let modificateur = ModificateurListeDeConfiance(stockage: faux)

        let resultat = modificateur.supprimerAppareil(
            nomAppareil: "Sac",
            idHache: idHache,
            date: date,
            mode: .code
        )

        #expect(resultat == .erreurSysteme)
    }

    @Test("Traduction des erreurs")
    func traductionDesErreurs() {
        #expect(InterpretationErreurModification.resultat(pour: ErreurListeDeConfiance.authentificationEchouee) == .echecAuthentification)
        #expect(InterpretationErreurModification.resultat(pour: ErreurListeDeConfiance.signatureInvalide) == .erreurSysteme)
        #expect(InterpretationErreurModification.resultat(pour: ErreurListeDeConfiance.versionPerimee) == .erreurSysteme)
    }
}