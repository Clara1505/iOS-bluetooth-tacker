#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-2 : Appairage par QR code et vérification d'empreinte (S1, S4, T4, E2, I4)")
struct AppairageQRTests {

    // MARK: - Aides de simulation côté iPhone (données 100 % fictives, CLAUDE.md §5)

    /// Simule la construction d'une demande d'appairage valide par un iPhone ayant scanné le QR code du Mac.
    private func creerDemandeIPhoneValide(
        clePriveeIPhone: P256.Signing.PrivateKey,
        chargeQR: ChargeUtileQRAppairage
    ) throws -> DemandeAppairageIPhone {
        let clePubliqueIPhoneBrute = clePriveeIPhone.publicKey.rawRepresentation
        let donneesASigner = ServiceAppairageCrypto.construireDonneesPreuveIPhone(
            nonceAppairage: chargeQR.nonceAppairage,
            empreinteClePubliqueMac: chargeQR.empreinteClePubliqueMac,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute
        )
        let signature = try clePriveeIPhone.signature(for: donneesASigner)
        return DemandeAppairageIPhone(
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
            nonceAppairage: chargeQR.nonceAppairage,
            signaturePreuveIPhone: signature.rawRepresentation
        )
    }

    // MARK: - 1. Parcours nominal complet d'appairage (MAC-2)

    @Test("Appairage complet valide : QR code -> preuve mutuelle ECDSA -> même code court -> confirmation")
    func parcoursNominalAppairageComplet() throws {
        let serviceMac = ServiceAppairageCrypto()
        #expect(!serviceMac.estAppaire)
        #expect(serviceMac.etat == .nonAppaire)

        // 1. Le Mac génère sa clé d'identité en RAM et son QR code
        let (_, donneesQR) = try serviceMac.demarrerNouvelAppairage(
            nomService: "CentraleAntiTraceur",
            port: 54321
        )

        // 2. L'iPhone scanne et décode le QR code
        let chargeQRScannee = try ChargeUtileQRAppairage.decoderDepuisQRCode(donneesQR)
        #expect(chargeQRScannee.version == ChargeUtileQRAppairage.versionAttendue)
        #expect(chargeQRScannee.port == 54321)

        // 3. L'iPhone envoie sa clé publique P-256 et sa preuve signée
        let clePriveeIPhone = P256.Signing.PrivateKey()
        let demandeIPhone = try creerDemandeIPhoneValide(
            clePriveeIPhone: clePriveeIPhone,
            chargeQR: chargeQRScannee
        )

        // 4. Le Mac vérifie la demande et passe en attente de confirmation visuelle du code court
        let reponseMac = try serviceMac.traiterDemandeAppairageIPhone(demandeIPhone)
        #expect(!serviceMac.estAppaire) // Pas encore appairé tant que l'humain n'a pas confirmé (E2)

        guard case .attenteConfirmationEmpreinte(let codeCourtMac, let empreinteHexMac) = serviceMac.etat else {
            Issue.record("Le Mac devrait être en état attenteConfirmationEmpreinte")
            return
        }

        // 5. L'iPhone vérifie la réponse du Mac (contre S1) et calcule le code court de son côté
        let verificationIPhone = try ServiceAppairageCrypto.verifierReponseMacCoteIPhone(
            reponse: reponseMac,
            chargeQR: chargeQRScannee,
            clePubliqueIPhoneBrute: clePriveeIPhone.publicKey.rawRepresentation
        )

        // Les deux écrans (Mac et iPhone) affichent exactement le même code court et la même empreinte
        #expect(verificationIPhone.codeCourt == codeCourtMac)
        #expect(verificationIPhone.empreinteMutuelleHex == empreinteHexMac)

        // 6. L'utilisateur confirme la correspondance sur le Mac
        try serviceMac.confirmerEmpreinteParUtilisateur()
        #expect(serviceMac.estAppaire)
        #expect(serviceMac.clePubliqueIPhoneAppaire?.rawRepresentation == clePriveeIPhone.publicKey.rawRepresentation)
    }

    // MARK: - 2. Tests de sécurité contre l'usurpation S1 (Homme du milieu / Faux Mac / Fausse signature)

    @Test("Contre S1 : L'iPhone rejette un faux Mac dont la clé publique ne correspond pas à l'empreinte du QR code")
    func rejetFauxMacHommeDuMilieu() throws {
        let serviceVraiMac = ServiceAppairageCrypto()
        let (chargeQRVraiMac, _) = try serviceVraiMac.demarrerNouvelAppairage(
            nomService: "CentraleAntiTraceur",
            port: 54321
        )

        let clePriveeIPhone = P256.Signing.PrivateKey()
        let clePubliqueIPhoneBrute = clePriveeIPhone.publicKey.rawRepresentation

        // Un attaquant M2 sur le réseau local génère sa propre clé P-256 et répond à la place du Mac
        let clePriveeFauxMac = P256.Signing.PrivateKey()
        let donneesSigneesFauxMac = ServiceAppairageCrypto.construireDonneesPreuveMac(
            nonceAppairage: chargeQRVraiMac.nonceAppairage,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
            clePubliqueMacBrute: clePriveeFauxMac.publicKey.rawRepresentation
        )
        let signatureFauxMac = try clePriveeFauxMac.signature(for: donneesSigneesFauxMac)

        let reponseFauxMac = ReponseAppairageMac(
            clePubliqueMacBrute: clePriveeFauxMac.publicKey.rawRepresentation,
            nonceAppairage: chargeQRVraiMac.nonceAppairage,
            signaturePreuveMac: signatureFauxMac.rawRepresentation
        )

        // L'iPhone détecte que SHA-256(cléFauxMac) != empreinte du QR code et rejette l'appairage
        #expect(throws: ErreurAppairageCrypto.empreinteMacNonConcordante) {
            _ = try ServiceAppairageCrypto.verifierReponseMacCoteIPhone(
                reponse: reponseFauxMac,
                chargeQR: chargeQRVraiMac,
                clePubliqueIPhoneBrute: clePubliqueIPhoneBrute
            )
        }
    }

    @Test("Contre S1/S2 : Le Mac rejette une demande d'appairage dont la signature ECDSA est falsifiée")
    func rejetDemandeIPhoneSignatureFalsifiee() throws {
        let serviceMac = ServiceAppairageCrypto()
        let (chargeQR, _) = try serviceMac.demarrerNouvelAppairage(
            nomService: "CentraleAntiTraceur",
            port: 54321
        )

        // Clé publique d'un iPhone, mais signée par une autre clé privée (usurpation)
        let cleVictime = P256.Signing.PrivateKey()
        let cleAttaquant = P256.Signing.PrivateKey()

        let donnees = ServiceAppairageCrypto.construireDonneesPreuveIPhone(
            nonceAppairage: chargeQR.nonceAppairage,
            empreinteClePubliqueMac: chargeQR.empreinteClePubliqueMac,
            clePubliqueIPhoneBrute: cleVictime.publicKey.rawRepresentation
        )
        let fausseSignature = try cleAttaquant.signature(for: donnees)

        let demandeUsurpee = DemandeAppairageIPhone(
            clePubliqueIPhoneBrute: cleVictime.publicKey.rawRepresentation,
            nonceAppairage: chargeQR.nonceAppairage,
            signaturePreuveIPhone: fausseSignature.rawRepresentation
        )

        #expect(throws: ErreurAppairageCrypto.signaturePreuveInvalide) {
            _ = try serviceMac.traiterDemandeAppairageIPhone(demandeUsurpee)
        }
        // Échec en sécurité : le service passe en état `.rejete` et n'est pas appairé
        #expect(!serviceMac.estAppaire)
        if case .rejete = serviceMac.etat {
            // Comportement attendu
        } else {
            Issue.record("Le service devrait avoir basculé en état .rejete après une signature invalide")
        }
    }

    // MARK: - 3. Tests de robustesse contre les QR codes malformés ou piégés (T4)

    @Test("Contre T4 : Rejet sans plantage d'un QR code vide, surdimensionné (> 1024 o) ou JSON invalide")
    func rejetQRCodeMalformeOuGeant() {
        // 1. QR code vide
        #expect(throws: ErreurAppairageCrypto.qrCodeVide) {
            _ = try ChargeUtileQRAppairage.decoderDepuisQRCode(Data())
        }

        // 2. QR code dépassant la taille maximale de 1 024 octets
        let qrGeant = Data(repeating: 0x41, count: ChargeUtileQRAppairage.tailleMaxOctetsQR + 1)
        #expect(throws: ErreurAppairageCrypto.qrCodeTropGrand(1_025)) {
            _ = try ChargeUtileQRAppairage.decoderDepuisQRCode(qrGeant)
        }

        // 3. QR code avec JSON corrompu
        let qrCorrompu = Data("{\"version\": 12345".utf8)
        #expect(throws: ErreurAppairageCrypto.formatJSONInvalide) {
            _ = try ChargeUtileQRAppairage.decoderDepuisQRCode(qrCorrompu)
        }
    }

    @Test("Contre T4 : Rejet d'un QR code avec version inconnue, port 0, mauvaise taille d'empreinte ou de nonce")
    func rejetChampsQRCodeHorsBornes() {
        let empreinteValide = Data(repeating: 0xAA, count: 32)
        let nonceValide = Data(repeating: 0xBB, count: 16)

        // Version inconnue
        let mauvaiseVersion = ChargeUtileQRAppairage(
            version: "autre-app-v9",
            nomService: "Centrale",
            port: 54321,
            empreinteClePubliqueMac: empreinteValide,
            nonceAppairage: nonceValide
        )
        #expect(throws: ErreurAppairageCrypto.versionProtocoleInconnue("autre-app-v9")) {
            try mauvaiseVersion.validerFormat()
        }

        // Port 0
        let portZero = ChargeUtileQRAppairage(
            nomService: "Centrale",
            port: 0,
            empreinteClePubliqueMac: empreinteValide,
            nonceAppairage: nonceValide
        )
        #expect(throws: ErreurAppairageCrypto.portInvalide) {
            try portZero.validerFormat()
        }

        // Empreinte tronquée (10 octets au lieu de 32)
        let empreinteCourte = ChargeUtileQRAppairage(
            nomService: "Centrale",
            port: 54321,
            empreinteClePubliqueMac: Data(repeating: 0xAA, count: 10),
            nonceAppairage: nonceValide
        )
        #expect(throws: ErreurAppairageCrypto.tailleEmpreinteInvalide(10)) {
            try empreinteCourte.validerFormat()
        }

        // Nonce trop court (8 octets au lieu de 16)
        let nonceCourt = ChargeUtileQRAppairage(
            nomService: "Centrale",
            port: 54321,
            empreinteClePubliqueMac: empreinteValide,
            nonceAppairage: Data(repeating: 0xBB, count: 8)
        )
        #expect(throws: ErreurAppairageCrypto.tailleNonceInvalide(8)) {
            try nonceCourt.validerFormat()
        }
    }

    // MARK: - 4. Tests de refus d'empreinte (S4, E2) et de purge en RAM (MAC-7, I4)

    @Test("Contre S4/E2 et I4 : Refus du code court par l'utilisateur et purge des clés en RAM")
    func refusEmpreinteEtPurgeRAM() throws {
        let fauxServiceReseau = FauxServiceReceptionAlertes()
        let serviceAppairage = ServiceAppairageCrypto()
        let viewModel = CentraleMacViewModel(
            serviceReception: fauxServiceReseau,
            serviceAppairage: serviceAppairage
        )

        // 1. Génération du QR code via le ViewModel
        viewModel.genererQRCodeAppairage()
        guard case .qrCodeAffiche(let chargeQR, _) = viewModel.etatAppairage else {
            Issue.record("Le QR code devrait être affiché")
            return
        }

        // 2. Réception d'une demande d'appairage valide
        let cleIPhone = P256.Signing.PrivateKey()
        let demande = try creerDemandeIPhoneValide(clePriveeIPhone: cleIPhone, chargeQR: chargeQR)
        let reponse = viewModel.recevoirDemandeAppairage(demande)
        #expect(reponse != nil)

        // 3. L'utilisateur constate que le code court diffère et clique sur "Refuser" (S4)
        viewModel.refuserAppairage()
        #expect(!serviceAppairage.estAppaire)
        #expect(serviceAppairage.clePubliqueIPhoneAppaire == nil)
        if case .rejete = viewModel.etatAppairage {
            // Attendu
        } else {
            Issue.record("L'état devrait être .rejete après refus de l'utilisateur")
        }

        // 4. Nouvel appairage accepté puis purge de fin de séance (MAC-7 / I4)
        viewModel.genererQRCodeAppairage()
        guard case .qrCodeAffiche(let chargeQR2, _) = viewModel.etatAppairage else {
            Issue.record("Le second QR code devrait être affiché")
            return
        }
        let demande2 = try creerDemandeIPhoneValide(clePriveeIPhone: cleIPhone, chargeQR: chargeQR2)
        _ = viewModel.recevoirDemandeAppairage(demande2)
        viewModel.confirmerAppairage()
        #expect(serviceAppairage.estAppaire)

        // Purge en fin de séance : la clé publique de l'iPhone et l'état d'appairage sont effacés de la RAM
        viewModel.purgerHistoriqueSession()
        #expect(!serviceAppairage.estAppaire)
        #expect(serviceAppairage.clePubliqueIPhoneAppaire == nil)
        #expect(viewModel.etatAppairage == .nonAppaire)
    }
}
#endif
