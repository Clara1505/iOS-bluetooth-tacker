#if canImport(Testing)
import Foundation
import Testing
@testable import CentraleMacCore

/// Bouchon (*mock*) du service de réception d'alertes pour tester `CentraleMacViewModel` en isolation.
///
/// Conforme à `CLAUDE.md` (§7) : chaque service est derrière un `protocol` pour pouvoir être remplacé
/// par un faux dans les tests unitaires.
final class FauxServiceReceptionAlertes: ServiceReceptionAlertesProtocol {
    var surChangementEtat: ((EtatServeurCentrale) -> Void)?
    var surReceptionAlerte: ((Alerte) -> Void)?
    var surRejetTrame: ((ErreurTransportCentrale) -> Void)?

    private(set) var nombreAppelsDemarrer = 0
    private(set) var nombreAppelsArreter = 0

    func demarrerEcoute() {
        nombreAppelsDemarrer += 1
        surChangementEtat?(.enEcoute(port: 54321))
    }

    func arreterEcoute() {
        nombreAppelsArreter += 1
        surChangementEtat?(.arrete)
    }

    /// Simule la réception d'une alerte validée provenant du réseau.
    func simulerAlerteRecue(_ alerte: Alerte) {
        surReceptionAlerte?(alerte)
    }

    /// Simule le rejet en sécurité d'une trame réseau malformée ou surdimensionnée.
    func simulerRejetTrame(_ erreur: ErreurTransportCentrale) {
        surRejetTrame?(erreur)
    }
}

@Suite("Tests unitaires MAC-1 : Réception des alertes, cadrage TCP et historique en RAM")
struct CentraleMacTests {

    // MARK: - Utilitaire de création de données fictives (aucune donnée réelle, CLAUDE.md §5)

    /// Génère un condensat HMAC-SHA256 fictif de 32 octets.
    private func creerIdHacheFictif(octet: UInt8 = 0xAB) -> Data {
        Data(repeating: octet, count: Alerte.tailleAttendueIdHache)
    }

    // MARK: - 1. Tests de validation du modèle Alerte (ARCH-3, I5, D3)

    @Test("Une alerte avec un idHache de 32 octets et au moins un balayage est valide")
    func validationAlerteValide() throws {
        let alerte = Alerte(
            niveau: .alerte,
            idHache: creerIdHacheFictif(),
            balayagesRefs: [UUID()]
        )
        try alerte.validerFormat()
        #expect(alerte.empreinteCourteAffichage == "abababab")
    }

    @Test("Une alerte avec un idHache de taille différente de 32 octets est rejetée (I5, D3)")
    func rejetIdHacheTailleInvalide() {
        let alerteTropCourte = Alerte(
            niveau: .info,
            idHache: Data([0x01, 0x02, 0x03]),
            balayagesRefs: [UUID()]
        )
        #expect(throws: ErreurValidationAlerte.tailleIdHacheInvalide(3)) {
            try alerteTropCourte.validerFormat()
        }
    }

    @Test("Une alerte sans balayage de référence ou dépassant le plafond est rejetée (D3)")
    func rejetBalayagesRefsInvalides() {
        let alerteSansBalayage = Alerte(
            niveau: .info,
            idHache: creerIdHacheFictif(),
            balayagesRefs: []
        )
        #expect(throws: ErreurValidationAlerte.nombreBalayagesRefsInvalide(0)) {
            try alerteSansBalayage.validerFormat()
        }

        let tropDeBalayages = (0...Alerte.nombreMaxBalayagesRefs).map { _ in UUID() }
        let alerteSaturee = Alerte(
            niveau: .critique,
            idHache: creerIdHacheFictif(),
            balayagesRefs: tropDeBalayages
        )
        #expect(throws: ErreurValidationAlerte.nombreBalayagesRefsInvalide(Alerte.nombreMaxBalayagesRefs + 1)) {
            try alerteSaturee.validerFormat()
        }
    }

    // MARK: - 2. Tests du cadrage TCP sur 4 octets (ARCH-2, D2, D3)

    @Test("Encapsulation et validation d'un en-tête de taille Big-Endian valide")
    func cadrageTrameValide() throws {
        let charge = Data("test-charge-utile".utf8)
        let trame = try CadrageTrameTCP.encapsuler(charge)

        #expect(trame.count == CadrageTrameTCP.tailleEntete + charge.count)
        let entete = trame.prefix(CadrageTrameTCP.tailleEntete)
        let tailleLue = try CadrageTrameTCP.validerEnteteTaille(Data(entete))
        #expect(tailleLue == charge.count)
    }

    @Test("Rejet immédiat d'un en-tête de taille 0 ou supérieure à 64 Ko contre la saturation mémoire (D2, D3)")
    func rejetEnteteTailleExcesOuZero() {
        // En-tête annonçant 0 octet
        let enteteZero = Data([0x00, 0x00, 0x00, 0x00])
        #expect(throws: ErreurTransportCentrale.trameVide) {
            _ = try CadrageTrameTCP.validerEnteteTaille(enteteZero)
        }

        // En-tête malveillant annonçant 4 Go (0xFFFFFFFF) pour tenter un DoS mémoire
        let enteteGeant = Data([0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: ErreurTransportCentrale.trameTropGrande(0xFFFF_FFFF)) {
            _ = try CadrageTrameTCP.validerEnteteTaille(enteteGeant)
        }

        // En-tête juste au-dessus de la limite de 64 Ko (65 537 octets = 0x00010001)
        let enteteDepassementUn = Data([0x00, 0x01, 0x00, 0x01])
        #expect(throws: ErreurTransportCentrale.trameTropGrande(65_537)) {
            _ = try CadrageTrameTCP.validerEnteteTaille(enteteDepassementUn)
        }
    }

    @Test("Rejet sans plantage d'une charge utile JSON malformée (D3)")
    func rejetJSONMalforme() {
        let octetsCorrompus = Data("{ json_invalide !!!".utf8)
        #expect(throws: ErreurTransportCentrale.decodageEchoue) {
            _ = try CadrageTrameTCP.decoderAlerte(depuis: octetsCorrompus)
        }
    }

    // MARK: - 3. Tests du Vue-Modèle et de l'historique en mémoire vive (MAC-1, MAC-7, I4, D2)

    @Test("Réception, tri décroissant, filtrage et purge de l'historique en mémoire vive")
    func cycleDeVieViewModelEtPurge() {
        let fauxService = FauxServiceReceptionAlertes()
        let viewModel = CentraleMacViewModel(serviceReception: fauxService)

        #expect(viewModel.etatServeur == .arrete)
        viewModel.demarrerCentrale()
        #expect(viewModel.etatServeur == .enEcoute(port: 54321))

        let alerteInfo = Alerte(
            niveau: .info,
            idHache: creerIdHacheFictif(octet: 0x11),
            balayagesRefs: [UUID()]
        )
        let alerteCritique = Alerte(
            niveau: .critique,
            idHache: creerIdHacheFictif(octet: 0x22),
            balayagesRefs: [UUID(), UUID()]
        )

        fauxService.simulerAlerteRecue(alerteInfo)
        fauxService.simulerAlerteRecue(alerteCritique)
        // L'envoi d'un doublon (même UUID) doit être ignoré
        fauxService.simulerAlerteRecue(alerteCritique)

        #expect(viewModel.alertesRecues.count == 2)
        // La plus récente est en tête (index 0)
        #expect(viewModel.alertesRecues.first?.id == alerteCritique.id)
        #expect(viewModel.alertesFiltrees(par: .critique).count == 1)
        #expect(viewModel.alertesFiltrees(par: .info).count == 1)
        #expect(viewModel.alertesFiltrees(par: .alerte).isEmpty)

        // Simulation d'une attaque par trame malformée rejetée
        fauxService.simulerRejetTrame(.trameTropGrande(999_999))
        #expect(viewModel.nombreTramesRejetees == 1)

        // Purge de fin de séance (MAC-7 / I4)
        viewModel.purgerHistoriqueSession()
        #expect(viewModel.alertesRecues.isEmpty)
        #expect(viewModel.nombreTramesRejetees == 0)
        #expect(viewModel.derniereErreurTransport == nil)
    }
}
#endif
