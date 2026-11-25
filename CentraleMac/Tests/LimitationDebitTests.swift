#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-6 : Rejet rapide des messages non authentifiés et limitation de débit (D2, E2)")
struct LimitationDebitTests {

    // MARK: - 1. Rejet pré-cryptographique en O(1) des messages non authentifiés (E2, D2)

    @Test("Contre E2 et D2 : Rejet immédiat en O(1) si aucun pair n'est appairé ou si le canal chiffré est fermé")
    func rejetRapideSansAppairageOuCanalFerme() {
        let limiteur = ServiceLimitationDebit(
            nombreMaxMessagesParFenetre: 10,
            dureeFenetreSecondes: 1.0,
            seuilEchecsAuthentificationConsecutifs: 3
        )
        let maintenant = Date()

        // 1. Pair non appairé -> rejet immédiat avant CryptoKit
        let decisionSansAppairage = limiteur.evaluerMessageEntrant(
            tailleOctets: 128,
            estPairAppaire: false,
            estCanalOuvert: false,
            dateReception: maintenant
        )
        #expect(decisionSansAppairage == .rejetePairNonAppaire)
        #expect(limiteur.nombreRejetsRapides == 1)
        #expect(limiteur.echecsAuthentificationConsecutifs == 1)

        // 2. Pair appairé mais canal chiffré non ouvert -> rejet immédiat avant CryptoKit
        let decisionCanalFerme = limiteur.evaluerMessageEntrant(
            tailleOctets: 128,
            estPairAppaire: true,
            estCanalOuvert: false,
            dateReception: maintenant
        )
        #expect(decisionCanalFerme == .rejeteCanalNonOuvert)
        #expect(limiteur.nombreRejetsRapides == 2)
        #expect(limiteur.echecsAuthentificationConsecutifs == 2)
    }

    @Test("Contre D2 et D3 : Rejet immédiat d'un paquet plus court que 29 octets (nonce + tag AES-GCM) ou > 64 Ko")
    func rejetRapideTailleImpossiblePourAESGCM() {
        let limiteur = ServiceLimitationDebit()
        let maintenant = Date()

        // Paquet de 10 octets (impossible pour AES-GCM qui exige au moins 12 o nonce + 16 o tag + 1 o = 29 o)
        let decisionTropCourt = limiteur.evaluerMessageEntrant(
            tailleOctets: 10,
            estPairAppaire: true,
            estCanalOuvert: true,
            dateReception: maintenant
        )
        #expect(decisionTropCourt == .rejeteTailleInvalide(10))

        // Paquet de 70 000 octets (> 65 536)
        let decisionTropGrand = limiteur.evaluerMessageEntrant(
            tailleOctets: 70_000,
            estPairAppaire: true,
            estCanalOuvert: true,
            dateReception: maintenant
        )
        #expect(decisionTropGrand == .rejeteTailleInvalide(70_000))
    }

    // MARK: - 2. Limitation de débit à fenêtre glissante contre un flood de messages (D2)

    @Test("Contre D2 : Envoi massif de messages (flood) -> rejet au-delà du plafond et reprise après la fenêtre")
    func limitationDebitFenetreGlissanteSousFlood() {
        let plafond = 5
        let limiteur = ServiceLimitationDebit(
            nombreMaxMessagesParFenetre: plafond,
            dureeFenetreSecondes: 1.0,
            seuilEchecsAuthentificationConsecutifs: 3
        )
        let instantZero = Date()

        // Les 5 premiers messages dans la même seconde sont autorisés
        for i in 0..<plafond {
            let decision = limiteur.evaluerMessageEntrant(
                tailleOctets: 200,
                estPairAppaire: true,
                estCanalOuvert: true,
                dateReception: instantZero.addingTimeInterval(Double(i) * 0.05)
            )
            #expect(decision == .autorise)
        }

        // Simulation d'un flood de 50 messages supplémentaires dans la même seconde : tous rejetés en O(1)
        for _ in 0..<50 {
            let decisionFlood = limiteur.evaluerMessageEntrant(
                tailleOctets: 200,
                estPairAppaire: true,
                estCanalOuvert: true,
                dateReception: instantZero.addingTimeInterval(0.5)
            )
            #expect(decisionFlood == .rejeteDebitDepasse(messagesDansFenetre: plafond, plafond: plafond))
        }
        #expect(limiteur.nombreRejetsRapides == 50)

        // 1,1 seconde plus tard (fenêtre glissante écoulée) : la centrale accepte à nouveau un message légitime
        let decisionApresFenetre = limiteur.evaluerMessageEntrant(
            tailleOctets: 200,
            estPairAppaire: true,
            estCanalOuvert: true,
            dateReception: instantZero.addingTimeInterval(1.1)
        )
        #expect(decisionApresFenetre == .autorise)
    }

    // MARK: - 3. Verrouillage automatique après 3 échecs d'authentification consécutifs (D2, E2)

    @Test("Contre D2 et E2 : Trois messages non authentifiés consécutifs verrouillent le canal dans CentraleMacViewModel")
    func verrouillageCanalApresTroisMessagesNonAuthentifies() throws {
        let fauxReseau = FauxServiceReceptionAlertes()
        let serviceAppairage = ServiceAppairageCrypto()
        let viewModel = CentraleMacViewModel(
            serviceReception: fauxReseau,
            serviceAppairage: serviceAppairage
        )

        // 1. Appairage MAC-2 et ouverture du canal chiffré MAC-3
        viewModel.genererQRCodeAppairage()
        guard case .qrCodeAffiche(let chargeQR, _) = viewModel.etatAppairage else {
            Issue.record("Le QR code devrait être affiché")
            return
        }

        let clePriveeIPhone = P256.Signing.PrivateKey()
        let clePubliqueIPhoneBrute = clePriveeIPhone.publicKey.rawRepresentation
        let donneesPreuve = ServiceAppairageCrypto.construireDonneesPreuveIPhone(
            nonceAppairage: chargeQR.nonceAppairage,
            empreinteClePubliqueMac: chargeQR.empreinteClePubliqueMac,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute
        )
        let sigPreuve = try clePriveeIPhone.signature(for: donneesPreuve)
        _ = viewModel.recevoirDemandeAppairage(
            DemandeAppairageIPhone(
                clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
                nonceAppairage: chargeQR.nonceAppairage,
                signaturePreuveIPhone: sigPreuve.rawRepresentation
            )
        )
        viewModel.confirmerAppairage()

        guard let clePubliqueMac = serviceAppairage.clePubliqueIdentiteMac else {
            Issue.record("Clé publique Mac attendue")
            return
        }

        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let donneesECDH = ServiceCanalChiffreCrypto.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
            clePubliqueIdentiteMacBrute: clePubliqueMac.rawRepresentation
        )
        let sigECDH = try clePriveeIPhone.signature(for: donneesECDH)
        _ = viewModel.ouvrirCanalChiffre(
            MessageEchangeECDHIPhone(
                clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
                signatureIdentiteIPhone: sigECDH.rawRepresentation
            )
        )

        // 2. Un attaquant M2 envoie 3 paquets non authentifiés (64 octets aléatoires non chiffrés avec la clé de session)
        let paquetFalsifie = Data(repeating: 0xAA, count: 64)
        let maintenant = Date()

        #expect(!viewModel.recevoirEvenementSigneEtChiffre(paquetFalsifie, dateReferenceMac: maintenant))
        #expect(!viewModel.recevoirEvenementSigneEtChiffre(paquetFalsifie, dateReferenceMac: maintenant))
        #expect(!viewModel.recevoirEvenementSigneEtChiffre(paquetFalsifie, dateReferenceMac: maintenant))

        // Au 3e échec consécutif, le canal chiffré est automatiquement coupé et verrouillé
        if case .verrouille = viewModel.etatCanalChiffre {
            // Comportement attendu
        } else {
            Issue.record("Le canal devrait être verrouillé après 3 messages non authentifiés consécutifs")
        }

        // Un 4e paquet est rejeté instantanément en O(1) par le limiteur sans même appeler CryptoKit
        #expect(!viewModel.recevoirEvenementSigneEtChiffre(paquetFalsifie, dateReferenceMac: maintenant))
        #expect(viewModel.derniereDecisionFiltrageRapide == .rejeteClientVerrouilleApresEchecs(echecsConsecutifs: 3))
    }
}
#endif
