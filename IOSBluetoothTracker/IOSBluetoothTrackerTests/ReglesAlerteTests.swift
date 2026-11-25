//
//  ReglesAlerteTests.swift
//  IOSBluetoothTrackerTests
//

import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Tests des niveaux d'alerte sur un balayage (IOS-5), avec des appareils fictifs.
@MainActor
struct ReglesAlerteTests {
    private let debut = Date(timeIntervalSince1970: 1_000_000)

    /// Crée un appareil fictif vu pendant `duree` secondes avec le signal `rssi`.
    private func appareil(rssi: Int, duree: TimeInterval, nom: String? = nil) -> AppareilDetecte {
        AppareilDetecte(
            identifiantSysteme: UUID(),
            nomAnnonce: nom,
            rssi: rssi,
            premiereDetection: debut,
            derniereDetection: debut + duree
        )
    }

    // MARK: - Niveau d'un appareil

    @Test func inconnuProcheEtResteDonneAlerte() {
        #expect(ReglesAlerte.niveau(pour: appareil(rssi: -50, duree: 28), estDeConfiance: false) == .alerte)
    }

    @Test func inconnuLointainDonneInfo() {
        #expect(ReglesAlerte.niveau(pour: appareil(rssi: -85, duree: 28), estDeConfiance: false) == .info)
    }

    @Test func inconnuProcheMaisVuBrievementDonneInfo() {
        #expect(ReglesAlerte.niveau(pour: appareil(rssi: -50, duree: 3), estDeConfiance: false) == .info)
    }

    /// Un appareil de confiance ne déclenche jamais d'alerte, même proche et présent tout le balayage.
    @Test func appareilDeConfianceNaPasDeNiveau() {
        #expect(ReglesAlerte.niveau(pour: appareil(rssi: -30, duree: 30), estDeConfiance: true) == nil)
    }

    // MARK: - Valeurs limites

    @Test func seuilsExactsDonnentAlerte() {
        let limite = appareil(rssi: ReglesAlerte.rssiProche, duree: ReglesAlerte.dureePresenceMinimale)
        #expect(ReglesAlerte.niveau(pour: limite, estDeConfiance: false) == .alerte)
    }

    @Test func justeSousLesSeuilsDonneInfo() {
        let tropFaible = appareil(rssi: ReglesAlerte.rssiProche - 1, duree: 30)
        let tropCourt = appareil(rssi: -40, duree: ReglesAlerte.dureePresenceMinimale - 0.001)
        #expect(ReglesAlerte.niveau(pour: tropFaible, estDeConfiance: false) == .info)
        #expect(ReglesAlerte.niveau(pour: tropCourt, estDeConfiance: false) == .info)
    }

    /// RSSI indisponible (ramené au minimum par le collecteur) : jamais considéré comme proche.
    @Test func rssiMinimumDonneInfo() {
        #expect(ReglesAlerte.niveau(pour: appareil(rssi: ReglesBalayage.rssiMinimum, duree: 30),
                                    estDeConfiance: false) == .info)
    }

    /// Dates incohérentes (dernière avant première) : durée négative, donc pas d'alerte, et pas de plantage.
    @Test func datesInverseesDonnentInfo() {
        let bizarre = AppareilDetecte(identifiantSysteme: UUID(), nomAnnonce: nil, rssi: -40,
                                      premiereDetection: debut + 30, derniereDetection: debut)
        #expect(ReglesAlerte.niveau(pour: bizarre, estDeConfiance: false) == .info)
    }

    // MARK: - Évaluation d'un balayage

    @Test func listeVideDonneAucuneEvaluation() {
        let evaluations = ReglesAlerte.evaluer([], estDeConfiance: { _ in false })
        #expect(evaluations.isEmpty)
        #expect(ReglesAlerte.niveauGlobal(evaluations) == nil)
    }

    @Test func triParGravitePuisSignalConfianceEnDernier() {
        let confiance = appareil(rssi: -30, duree: 30, nom: "Confiance")
        let info = appareil(rssi: -45, duree: 2, nom: "Info")
        let alerte = appareil(rssi: -55, duree: 25, nom: "Alerte")
        let infoFaible = appareil(rssi: -90, duree: 30, nom: "Info faible")
        let evaluations = ReglesAlerte.evaluer(
            [infoFaible, confiance, info, alerte],
            estDeConfiance: { $0.id == confiance.id }
        )
        #expect(evaluations.map(\.appareil.nomAnnonce) == ["Alerte", "Info", "Info faible", "Confiance"])
        #expect(evaluations.map(\.niveau) == [.alerte, .info, .info, nil])
    }

    @Test func leNiveauLePlusEleveLEmporte() {
        let evaluations = ReglesAlerte.evaluer(
            [appareil(rssi: -90, duree: 2), appareil(rssi: -50, duree: 25)],
            estDeConfiance: { _ in false }
        )
        #expect(ReglesAlerte.niveauGlobal(evaluations) == .alerte)
    }

    @Test func seulementDesAppareilsDeConfianceDonneAucunNiveau() {
        let evaluations = ReglesAlerte.evaluer(
            [appareil(rssi: -40, duree: 30), appareil(rssi: -50, duree: 30)],
            estDeConfiance: { _ in true }
        )
        #expect(ReglesAlerte.niveauGlobal(evaluations) == nil)
    }

    // MARK: - Vue-modèle

    @Test func leVueModeleEvalueUnBalayageComplet() async {
        let proche = appareil(rssi: -50, duree: 25)
        let vueModele = BalayageVueModele(service: FauxServiceBalayage(resultat: .complet([proche])))
        await vueModele.lancerControle()
        #expect(vueModele.evaluations.map(\.niveau) == [.alerte])
        #expect(vueModele.niveauGlobal == .alerte)
    }

    /// D4 : un contrôle impossible ne produit aucune évaluation (ni « aucun appareil inconnu »).
    @Test func controleImpossibleNeProduitAucuneEvaluation() async {
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .controleImpossible(.interrompu))
        )
        await vueModele.lancerControle()
        #expect(vueModele.evaluations.isEmpty)
        #expect(vueModele.resultat == .controleImpossible(.interrompu))
    }

    @Test func leVueModeleUtiliseLaListeDeConfiance() async {
        let proche = appareil(rssi: -50, duree: 25)
        let stockage = StockageFictif(idsHaches: [HacheurFictif().hacher(proche.identifiantSysteme)])
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .complet([proche])),
            verificateur: VerificateurConfiance(stockage: stockage, hacheur: HacheurFictif())
        )
        await vueModele.lancerControle()
        #expect(vueModele.evaluations.map(\.niveau) == [nil])
        #expect(vueModele.niveauGlobal == nil)
    }

    /// Échec en sécurité : une liste illisible ou falsifiée ne rend aucun appareil de confiance.
    @Test func listeIllisibleLaisseLAppareilEnAlerte() async {
        let proche = appareil(rssi: -50, duree: 25)
        let stockage = StockageFictif(idsHaches: [HacheurFictif().hacher(proche.identifiantSysteme)])
        stockage.erreurLire = ErreurListeDeConfiance.signatureInvalide
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .complet([proche])),
            verificateur: VerificateurConfiance(stockage: stockage, hacheur: HacheurFictif())
        )
        await vueModele.lancerControle()
        #expect(vueModele.niveauGlobal == .alerte)
    }

    /// La liste est relue à chaque contrôle : un appareil ajouté entre deux contrôles n'alerte plus.
    @Test func laListeEstRelueAChaqueControle() async {
        let proche = appareil(rssi: -50, duree: 25)
        let stockage = StockageFictif(idsHaches: [])
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .complet([proche])),
            verificateur: VerificateurConfiance(stockage: stockage, hacheur: HacheurFictif())
        )
        await vueModele.lancerControle()
        #expect(vueModele.niveauGlobal == .alerte)

        stockage.idsHaches = [HacheurFictif().hacher(proche.identifiantSysteme)]
        await vueModele.lancerControle()
        #expect(vueModele.niveauGlobal == nil)
    }

    /// Sans vérificateur (liste non disponible), tout appareil est inconnu.
    @Test func sansVerificateurToutAppareilEstInconnu() async {
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .complet([appareil(rssi: -50, duree: 25)]))
        )
        await vueModele.lancerControle()
        #expect(vueModele.niveauGlobal == .alerte)
    }
}

// MARK: - Faux pour la liste de confiance (aucune crypto dans ces tests)

/// Stockage en mémoire qui renvoie une liste construite à partir d'identifiants hachés fictifs.
private final class StockageFictif: StockageListeDeConfiance {
    var idsHaches: [Data]
    var erreurLire: Error?

    init(idsHaches: [Data]) {
        self.idsHaches = idsHaches
    }

    func lire() throws -> ContenuListe {
        if let erreurLire { throw erreurLire }
        var contenu = ContenuListe()
        contenu.appareils = idsHaches.map { AppareilDeConfiance(idHache: $0, nom: "Fictif", ajouteLe: Date(timeIntervalSince1970: 0)) }
        return contenu
    }

    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {}

    func reinitialiser() throws {}
}

/// Hacheur fictif : l'identifiant en texte, sans crypto (le vrai hacheur relève de TRU-6).
private struct HacheurFictif: HacheurIdentifiant {
    func hacher(_ identifiant: UUID) -> Data {
        Data(identifiant.uuidString.utf8)
    }
}
