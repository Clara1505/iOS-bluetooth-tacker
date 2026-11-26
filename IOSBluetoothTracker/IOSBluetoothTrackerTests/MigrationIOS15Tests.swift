import Combine
import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Tests de caractérisation de la migration vers iOS 15 (PM-11).
///
/// Avec `@Observable`, SwiftUI se rafraîchissait tout seul. Avec `ObservableObject`, l'écran ne
/// se met à jour que si le vue-modèle annonce ses changements (`@Published`) : ces tests
/// vérifient cette annonce, qui n'était pas testée avant la migration.
@MainActor
@Suite("Migration iOS 15 (PM-11)")
struct MigrationIOS15Tests {

    private func appareilFictif() -> AppareilDetecte {
        AppareilDetecte(
            identifiantSysteme: UUID(),
            nomAnnonce: "Appareil fictif",
            rssi: -60,
            premiereDetection: Date(timeIntervalSince1970: 1_800_000_000),
            derniereDetection: Date(timeIntervalSince1970: 1_800_000_030)
        )
    }

    // MARK: - Annonce des changements

    @Test("Le vue-modèle du balayage annonce ses changements pendant un contrôle")
    func balayageAnnonceLesChangements() async {
        let vueModele = BalayageVueModele(service: FauxServiceBalayage(resultat: .complet([appareilFictif()])))
        var annonces = 0
        let abonnement = vueModele.objectWillChange.sink { annonces += 1 }

        await vueModele.lancerControle()

        // enCours (vrai puis faux), resultat et evaluations changent : au moins une annonce par changement.
        #expect(annonces >= 3)
        abonnement.cancel()
    }

    @Test("Le vue-modèle de l'enrôlement annonce la saisie du nom")
    func enrolementAnnonceLaSaisie() {
        let stockage = StockageVide()
        let vueModele = EnrolementVueModele(
            modificateur: ModificateurListeDeConfiance(stockage: stockage),
            hacheur: HacheurVide(),
            mode: { .biometrie }
        )
        var annonces = 0
        let abonnement = vueModele.objectWillChange.sink { annonces += 1 }

        vueModele.nomSaisi = "Sac"

        #expect(annonces == 1)
        abonnement.cancel()
    }

    @Test("Le vue-modèle de la liste annonce le chargement")
    func listeAnnonceLeChargement() {
        let stockage = StockageVide()
        let vueModele = ListeConfianceVueModele(
            stockage: stockage,
            modificateur: ModificateurListeDeConfiance(stockage: stockage),
            mode: { .biometrie }
        )
        var annonces = 0
        let abonnement = vueModele.objectWillChange.sink { annonces += 1 }

        vueModele.charger()

        #expect(annonces >= 1)
        abonnement.cancel()
    }

    // MARK: - Évaluation du balayage

    @Test("Un contrôle complet évalue chaque appareil et donne un niveau global")
    func controleCompletEvalue() async {
        let vueModele = BalayageVueModele(service: FauxServiceBalayage(resultat: .complet([appareilFictif()])))

        await vueModele.lancerControle()

        #expect(vueModele.evaluations.count == 1)
        // Sans vérificateur, tout appareil est inconnu (échec en sécurité).
        #expect(vueModele.niveauGlobal != nil)
    }

    @Test("Un contrôle impossible n'évalue rien et ne donne aucun niveau (D4)")
    func controleImpossibleNEvaluePas() async {
        let vueModele = BalayageVueModele(service: FauxServiceBalayage(resultat: .controleImpossible(.bluetoothCoupe)))

        await vueModele.lancerControle()

        #expect(vueModele.evaluations.isEmpty)
        #expect(vueModele.niveauGlobal == nil)
    }

    // MARK: - Format sérialisé du mode d'authentification

    @Test("Le mode biométrie reste sérialisé « faceID » (format signé inchangé)")
    func formatSerialiseInchange() throws {
        let donnees = try JSONEncoder().encode(ModeAuthentification.biometrie)
        #expect(String(decoding: donnees, as: UTF8.self) == "\"faceID\"")
    }

    @Test("Une entrée d'historique déjà écrite avec « faceID » est relue comme biométrie")
    func ancienneValeurRelue() throws {
        let donnees = Data("\"faceID\"".utf8)
        #expect(try JSONDecoder().decode(ModeAuthentification.self, from: donnees) == .biometrie)
    }

    @Test("Le mode « code » est inchangé")
    func modeCodeInchange() throws {
        let donnees = try JSONEncoder().encode(ModeAuthentification.code)
        #expect(String(decoding: donnees, as: UTF8.self) == "\"code\"")
    }

    @Test("Une valeur inconnue est refusée au décodage")
    func valeurInconnueRefusee() {
        let donnees = Data("\"empreinte\"".utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ModeAuthentification.self, from: donnees)
        }
    }

    @Test("Les libellés affichés ne parlent plus seulement de Face ID")
    func libelles() {
        #expect(ModeAuthentification.biometrie.libelle == "biométrie")
        #expect(ModeAuthentification.code.libelle == "code")
    }
}

/// Stockage minimal en mémoire pour ces tests.
private final class StockageVide: StockageListeDeConfiance {
    private var contenu = ContenuListe()
    func lire() throws -> ContenuListe { contenu }
    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {
        var copie = contenu
        copie.ajouterHistorique(entree)
        transformation(&copie)
        contenu = copie
    }
    func reinitialiser() throws { contenu = ContenuListe() }
}

/// Hacheur fictif : pas de crypto dans ces tests.
private struct HacheurVide: HacheurIdentifiant {
    func hacher(_ identifiant: UUID) -> Data { Data(identifiant.uuidString.utf8) }
}
