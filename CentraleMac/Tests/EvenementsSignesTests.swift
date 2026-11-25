#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-4 : Événements signés P-256 ECDSA, horodatage ±60 s, nonce et compteur anti-rejeu")
struct EvenementsSignesTests {

    // MARK: - Aides de simulation (données 100 % fictives, CLAUDE.md §5)

    /// Crée une alerte fictive valide avec un condensat HMAC-SHA256 de 32 octets.
    private func creerAlerteFictive(
        niveau: NiveauAlerte = .alerte,
        octetIdHache: UInt8 = 0x42,
        date: Date = Date()
    ) -> Alerte {
        Alerte(
            niveau: niveau,
            idHache: Data(repeating: octetIdHache, count: Alerte.tailleAttendueIdHache),
            balayagesRefs: [UUID()],
            date: date
        )
    }

    /// Réalise l'appairage `MAC-2` entre un signataire iPhone et le service Mac.
    private func preparerAppairageEtVerificateur() throws -> (
        serviceAppairage: ServiceAppairageCrypto,
        verificateurMac: ServiceEvenementsSignesCrypto,
        signataireIPhone: SignataireMemoireP256,
        clePriveeIPhone: P256.Signing.PrivateKey
    ) {
        let serviceAppairage = ServiceAppairageCrypto()
        let (chargeQR, _) = try serviceAppairage.demarrerNouvelAppairage(
            nomService: "CentraleAntiTraceur",
            port: 54321
        )

        let clePriveeIPhone = P256.Signing.PrivateKey()
        let signataireIPhone = SignataireMemoireP256(clePrivee: clePriveeIPhone)
        let clePubliqueIPhoneBrute = clePriveeIPhone.publicKey.rawRepresentation

        let donneesPreuve = ServiceAppairageCrypto.construireDonneesPreuveIPhone(
            nonceAppairage: chargeQR.nonceAppairage,
            empreinteClePubliqueMac: chargeQR.empreinteClePubliqueMac,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute
        )
        let signaturePreuve = try clePriveeIPhone.signature(for: donneesPreuve)

        let demande = DemandeAppairageIPhone(
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
            nonceAppairage: chargeQR.nonceAppairage,
            signaturePreuveIPhone: signaturePreuve.rawRepresentation
        )
        _ = try serviceAppairage.traiterDemandeAppairageIPhone(demande)
        try serviceAppairage.confirmerEmpreinteParUtilisateur()

        let verificateurMac = ServiceEvenementsSignesCrypto(serviceAppairage: serviceAppairage)
        return (serviceAppairage, verificateurMac, signataireIPhone, clePriveeIPhone)
    }

    // MARK: - 1. Parcours nominal : signature ECDSA P-256 et croissance du compteur (S2, R1, T1, T2)

    @Test("Acceptation d'événements signés valides avec compteur strictement croissant (1 puis 2)")
    func acceptationEvenementsSignesValides() throws {
        let (_, verificateurMac, signataireIPhone, _) = try preparerAppairageEtVerificateur()
        let maintenant = Date()

        #expect(verificateurMac.dernierCompteurAccepte == 0)

        // Événement n°1 (compteur = 1)
        let alerte1 = creerAlerteFictive(niveau: .info, octetIdHache: 0x11, date: maintenant)
        let evenement1 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerte1,
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        let acceptee1 = try verificateurMac.verifierEtAccepterEvenement(
            evenement1,
            dateReferenceMac: maintenant
        )
        #expect(acceptee1 == alerte1)
        #expect(verificateurMac.dernierCompteurAccepte == 1)
        #expect(verificateurMac.nombreNoncesVus == 1)

        // Événement n°2 (compteur = 2)
        let alerte2 = creerAlerteFictive(niveau: .critique, octetIdHache: 0x22, date: maintenant)
        let evenement2 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerte2,
            compteur: 2,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        let acceptee2 = try verificateurMac.verifierEtAccepterEvenement(
            evenement2,
            dateReferenceMac: maintenant
        )
        #expect(acceptee2 == alerte2)
        #expect(verificateurMac.dernierCompteurAccepte == 2)
        #expect(verificateurMac.nombreNoncesVus == 2)
    }

    // MARK: - 2. Tests anti-rejeu T2 : rejeu exact, compteur inférieur ou égal, nonce réutilisé, horodatage hors ±60 s

    @Test("Contre T2 : Rejet d'un message valide rejoué ou d'un compteur inférieur ou égal")
    func rejetRejeuEtCompteurNonCroissant() throws {
        let (_, verificateurMac, signataireIPhone, _) = try preparerAppairageEtVerificateur()
        let maintenant = Date()

        let evenementCompteur2 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: maintenant),
            compteur: 2,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        _ = try verificateurMac.verifierEtAccepterEvenement(
            evenementCompteur2,
            dateReferenceMac: maintenant
        )
        #expect(verificateurMac.dernierCompteurAccepte == 2)

        // 1. Rejeu exact du même message (compteur = 2 <= 2)
        #expect(throws: ErreurEvenementSigneCrypto.compteurNonStrictementCroissant(recu: 2, dernierAccepte: 2)) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementCompteur2,
                dateReferenceMac: maintenant
            )
        }

        // 2. Envoi d'un ancien message valide avec un compteur inférieur (compteur = 1 <= 2)
        let evenementAncienCompteur1 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: maintenant),
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        #expect(throws: ErreurEvenementSigneCrypto.compteurNonStrictementCroissant(recu: 1, dernierAccepte: 2)) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementAncienCompteur1,
                dateReferenceMac: maintenant
            )
        }
    }

    @Test("Contre T2 : Rejet d'un événement qui réutilise un nonce déjà vu malgré un compteur supérieur")
    func rejetNonceReutilise() throws {
        let (_, verificateurMac, signataireIPhone, _) = try preparerAppairageEtVerificateur()
        let maintenant = Date()
        let nonceFixe = Data(repeating: 0x77, count: EvenementAlerteSigne.tailleNonceOctets)

        let evenement1 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: maintenant),
            compteur: 1,
            nonce: nonceFixe,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        _ = try verificateurMac.verifierEtAccepterEvenement(evenement1, dateReferenceMac: maintenant)

        // Même nonce réutilisé avec compteur = 2
        let evenement2MemeNonce = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: maintenant),
            compteur: 2,
            nonce: nonceFixe,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        #expect(throws: ErreurEvenementSigneCrypto.nonceDejaUtilise) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenement2MemeNonce,
                dateReferenceMac: maintenant
            )
        }
    }

    @Test("Contre T2 : Rejet d'un événement dont l'horodatage dépasse la tolérance de ±60 secondes")
    func rejetHorodatageHorsTolerance60Secondes() throws {
        let (_, verificateurMac, signataireIPhone, _) = try preparerAppairageEtVerificateur()
        let horlogeMac = Date()

        // 1. Événement daté d'il y a 65 secondes (> 60 s)
        let dateTropAncienne = horlogeMac.addingTimeInterval(-65)
        let evenementTropAncien = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: dateTropAncienne),
            compteur: 1,
            horodatage: dateTropAncienne,
            signataire: signataireIPhone
        )
        #expect(throws: ErreurEvenementSigneCrypto.horodatageHorsTolerance(ecartSecondes: 65)) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementTropAncien,
                dateReferenceMac: horlogeMac
            )
        }
        // Le compteur ne doit pas avoir avancé après ce rejet
        #expect(verificateurMac.dernierCompteurAccepte == 0)

        // 2. Événement daté de +70 secondes dans le futur (> 60 s)
        let dateTropFuture = horlogeMac.addingTimeInterval(70)
        let evenementTropFutur = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(date: dateTropFuture),
            compteur: 1,
            horodatage: dateTropFuture,
            signataire: signataireIPhone
        )
        #expect(throws: ErreurEvenementSigneCrypto.horodatageHorsTolerance(ecartSecondes: 70)) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementTropFutur,
                dateReferenceMac: horlogeMac
            )
        }
        #expect(verificateurMac.dernierCompteurAccepte == 0)
    }

    // MARK: - 3. Tests contre l'usurpation S2 et l'altération T1 (Signature invalide ou niveau modifié)

    @Test("Contre S2 et D2 : Un message signé par une autre clé est rejeté sans faire avancer le compteur")
    func rejetSignatureAutreCleSansDesynchroniserCompteur() throws {
        let (_, verificateurMac, signataireLegitime, _) = try preparerAppairageEtVerificateur()
        let maintenant = Date()

        // Un attaquant M2 signe un événement avec sa propre clé P-256 et un compteur énorme (9999)
        // pour tenter d'injecter une fausse alerte ou de bloquer le compteur de la centrale
        let signataireAttaquant = SignataireMemoireP256()
        let evenementFalsifie = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(niveau: .info, date: maintenant),
            compteur: 9_999,
            horodatage: maintenant,
            signataire: signataireAttaquant
        )

        #expect(throws: ErreurEvenementSigneCrypto.signatureECDSAInvalide) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementFalsifie,
                dateReferenceMac: maintenant
            )
        }
        // Le compteur est resté à 0 : l'iPhone légitime peut toujours envoyer son compteur = 1
        #expect(verificateurMac.dernierCompteurAccepte == 0)

        let evenementLegitime = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: creerAlerteFictive(niveau: .critique, date: maintenant),
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireLegitime
        )
        _ = try verificateurMac.verifierEtAccepterEvenement(
            evenementLegitime,
            dateReferenceMac: maintenant
        )
        #expect(verificateurMac.dernierCompteurAccepte == 1)
    }

    @Test("Contre T1 : Toute modification du niveau de l'alerte (ex. critique -> info) invalide la signature ECDSA")
    func rejetModificationNiveauAlerteApresSignature() throws {
        let (_, verificateurMac, signataireIPhone, _) = try preparerAppairageEtVerificateur()
        let maintenant = Date()

        // L'iPhone signe une alerte de niveau `.critique`
        let alerteCritique = creerAlerteFictive(niveau: .critique, date: maintenant)
        let evenementSigne = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerteCritique,
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireIPhone
        )

        // Un attaquant remplace le niveau `.critique` par `.info` en conservant le même ID et la même signature
        let alerteAdoucie = Alerte(
            id: alerteCritique.id,
            niveau: .info,
            idHache: alerteCritique.idHache,
            balayagesRefs: alerteCritique.balayagesRefs,
            date: alerteCritique.date
        )
        let evenementAltere = EvenementAlerteSigne(
            alerte: alerteAdoucie,
            compteur: evenementSigne.compteur,
            nonce: evenementSigne.nonce,
            horodatage: evenementSigne.horodatage,
            signatureECDSA: evenementSigne.signatureECDSA
        )

        #expect(throws: ErreurEvenementSigneCrypto.signatureECDSAInvalide) {
            _ = try verificateurMac.verifierEtAccepterEvenement(
                evenementAltere,
                dateReferenceMac: maintenant
            )
        }
    }

    // MARK: - 4. Test de bout en bout de la chaîne sécurisée complète (MAC-1 + MAC-2 + MAC-3 + MAC-4 + MAC-7)

    @Test("Chaîne sécurisée complète dans CentraleMacViewModel : Appairage QR -> Canal AES-GCM -> Événement signé -> Purge")
    func chaineSecuriseeCompleteBoutEnBout() throws {
        let (serviceAppairage, _, signataireIPhone, clePriveeIPhone) = try preparerAppairageEtVerificateur()
        guard let cleIdentiteMac = serviceAppairage.clePubliqueIdentiteMac else {
            Issue.record("La clé publique du Mac devrait être disponible")
            return
        }

        let fauxReseau = FauxServiceReceptionAlertes()
        let viewModel = CentraleMacViewModel(
            serviceReception: fauxReseau,
            serviceAppairage: serviceAppairage
        )

        // 1. Ouverture du canal chiffré (MAC-3)
        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let donneesECDH = ServiceCanalChiffreCrypto.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
            clePubliqueIdentiteMacBrute: cleIdentiteMac.rawRepresentation
        )
        let sigECDH = try clePriveeIPhone.signature(for: donneesECDH)
        let messageECDH = MessageEchangeECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
            signatureIdentiteIPhone: sigECDH.rawRepresentation
        )

        guard let reponseECDHMac = viewModel.ouvrirCanalChiffre(messageECDH) else {
            Issue.record("Le canal chiffré aurait dû s'ouvrir")
            return
        }
        let clesSessionIPhone = try ServiceCanalChiffreCrypto.finaliserCanalCoteIPhone(
            reponseMac: reponseECDHMac,
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac,
            clePubliqueIdentiteIPhoneBrute: clePriveeIPhone.publicKey.rawRepresentation
        )

        // 2. Signature d'un événement (MAC-4) puis chiffrement en AES-256-GCM (MAC-3)
        let maintenant = Date()
        let alerte = creerAlerteFictive(niveau: .critique, octetIdHache: 0xEF, date: maintenant)
        let evenementSigne = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerte,
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        let blocChiffreEtSigne = try ServiceEvenementsSignesCrypto.encoderEtChiffrerEvenementCoteIPhone(
            evenement: evenementSigne,
            cleSessionIPhoneVersMac: clesSessionIPhone.cleIPhoneVersMac
        )

        // 3. Réception par le ViewModel Mac : déchiffrement AES-GCM + vérification ECDSA + anti-rejeu
        let accepte = viewModel.recevoirEvenementSigneEtChiffre(
            blocChiffreEtSigne,
            dateReferenceMac: maintenant
        )
        #expect(accepte)
        #expect(viewModel.alertesRecues.count == 1)
        #expect(viewModel.dernierCompteurAntiRejeu == 1)

        // 4. Tentative de rejouer le même paquet chiffré (T2) -> rejeté !
        let rejeuAccepte = viewModel.recevoirEvenementSigneEtChiffre(
            blocChiffreEtSigne,
            dateReferenceMac: maintenant
        )
        #expect(!rejeuAccepte)
        #expect(viewModel.alertesRecues.count == 1)
        #expect(viewModel.nombreTramesRejetees == 1)

        // 5. Purge de fin de séance (MAC-7 / I4)
        viewModel.purgerHistoriqueSession()
        #expect(viewModel.alertesRecues.isEmpty)
        #expect(viewModel.dernierCompteurAntiRejeu == 0)
        #expect(viewModel.etatCanalChiffre == .ferme)
        #expect(viewModel.etatAppairage == .nonAppaire)
    }
}
#endif
