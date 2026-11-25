#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-3 : Canal chiffré (ECDH éphémère signé, HKDF-SHA256 1 clé/sens, AES-256-GCM)")
struct CanalChiffreTests {

    // MARK: - Aides de simulation (données 100 % fictives, CLAUDE.md §5)

    /// Réalise un appairage complet `MAC-2` entre un iPhone fictif et le service Mac,
    /// et retourne le service d'appairage confirmé ainsi que la clé privée d'identité de l'iPhone.
    private func effectuerAppairagePrealable() throws -> (
        serviceAppairage: ServiceAppairageCrypto,
        clePriveeIdentiteIPhone: P256.Signing.PrivateKey,
        clePubliqueIdentiteMac: P256.Signing.PublicKey
    ) {
        let serviceAppairage = ServiceAppairageCrypto()
        let (chargeQR, _) = try serviceAppairage.demarrerNouvelAppairage(
            nomService: "CentraleAntiTraceur",
            port: 54321
        )

        let clePriveeIPhone = P256.Signing.PrivateKey()
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
        let reponseMac = try serviceAppairage.traiterDemandeAppairageIPhone(demande)
        let verification = try ServiceAppairageCrypto.verifierReponseMacCoteIPhone(
            reponse: reponseMac,
            chargeQR: chargeQR,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute
        )
        try serviceAppairage.confirmerEmpreinteParUtilisateur()

        return (serviceAppairage, clePriveeIPhone, verification.clePubliqueMac)
    }

    /// Construit un message d'échange ECDH signé valide côté iPhone.
    private func creerMessageECDHIPhoneValide(
        clePriveeEphemeralIPhone: P256.KeyAgreement.PrivateKey,
        clePriveeIdentiteIPhone: P256.Signing.PrivateKey,
        clePubliqueIdentiteMac: P256.Signing.PublicKey
    ) throws -> MessageEchangeECDHIPhone {
        let cleEphBrute = clePriveeEphemeralIPhone.publicKey.rawRepresentation
        let donneesASigner = ServiceCanalChiffreCrypto.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphBrute,
            clePubliqueIdentiteMacBrute: clePubliqueIdentiteMac.rawRepresentation
        )
        let signature = try clePriveeIdentiteIPhone.signature(for: donneesASigner)
        return MessageEchangeECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphBrute,
            signatureIdentiteIPhone: signature.rawRepresentation
        )
    }

    // MARK: - 1. Parcours nominal complet : Handshake ECDH signé -> HKDF -> AES-256-GCM bidirectionnel

    @Test("Ouverture nominale du canal chiffré et échange bidirectionnel AES-256-GCM (I1, T1)")
    func ouvertureCanalEtChiffrementBidirectionnel() throws {
        let (serviceAppairage, cleIdentiteIPhone, cleIdentiteMac) = try effectuerAppairagePrealable()
        let serviceCanalMac = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)
        #expect(!serviceCanalMac.estOuvert)
        #expect(serviceCanalMac.etat == .ferme)

        // 1. L'iPhone génère sa paire ECDH P-256 éphémère et la signe avec sa clé d'identité
        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let messageECDHIPhone = try creerMessageECDHIPhoneValide(
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePriveeIdentiteIPhone: cleIdentiteIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac
        )

        // 2. Le Mac vérifie la signature, génère sa propre paire ECDH éphémère, dérive les clés HKDF et répond
        let reponseECDHMac = try serviceCanalMac.etablirCanalDepuisMessageIPhone(messageECDHIPhone)
        #expect(serviceCanalMac.estOuvert)

        // 3. L'iPhone vérifie la signature du Mac et dérive les mêmes clés directionnelles HKDF-SHA256
        let clesIPhone = try ServiceCanalChiffreCrypto.finaliserCanalCoteIPhone(
            reponseMac: reponseECDHMac,
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac,
            clePubliqueIdentiteIPhoneBrute: cleIdentiteIPhone.publicKey.rawRepresentation
        )

        // 4. Sens iPhone -> Mac : l'iPhone chiffre une alerte, le Mac la déchiffre
        let messageClairIPhone = Data("Alerte critique traceur inconnu".utf8)
        let blocChiffreIPhone = try ServiceCanalChiffreCrypto.chiffrerAESGCM(
            donneesClaires: messageClairIPhone,
            cle: clesIPhone.cleIPhoneVersMac,
            donneesAssociees: ServiceCanalChiffreCrypto.aadDirectionIPhoneVersMac
        )
        // Vérifie que le texte chiffré ne contient pas le texte clair (confidentialité I1)
        #expect(blocChiffreIPhone != messageClairIPhone)

        let dechiffreParMac = try serviceCanalMac.dechiffrerMessageDepuisIPhone(blocChiffreIPhone)
        #expect(dechiffreParMac == messageClairIPhone)

        // 5. Sens Mac -> iPhone : le Mac chiffre un acquittement, l'iPhone le déchiffre
        let messageClairMac = Data("Acquittement centrale Mac".utf8)
        let blocChiffreMac = try serviceCanalMac.chiffrerMessageVersIPhone(messageClairMac)
        let dechiffreParIPhone = try ServiceCanalChiffreCrypto.dechiffrerAESGCM(
            donneesCombinees: blocChiffreMac,
            cle: clesIPhone.cleMacVersIPhone,
            donneesAssociees: ServiceCanalChiffreCrypto.aadDirectionMacVersIPhone
        )
        #expect(dechiffreParIPhone == messageClairMac)
    }

    // MARK: - 2. Tests d'intégrité AES-256-GCM contre T1 (Altération d'un octet en transit)

    @Test("Contre T1 : Un seul octet modifié dans le message chiffré fait échouer le déchiffrement AES-GCM")
    func rejetMessageChiffreAltereUnOctet() throws {
        let (serviceAppairage, cleIdentiteIPhone, cleIdentiteMac) = try effectuerAppairagePrealable()
        let serviceCanalMac = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)

        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let messageECDH = try creerMessageECDHIPhoneValide(
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePriveeIdentiteIPhone: cleIdentiteIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac
        )
        let reponseMac = try serviceCanalMac.etablirCanalDepuisMessageIPhone(messageECDH)
        let clesIPhone = try ServiceCanalChiffreCrypto.finaliserCanalCoteIPhone(
            reponseMac: reponseMac,
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac,
            clePubliqueIdentiteIPhoneBrute: cleIdentiteIPhone.publicKey.rawRepresentation
        )

        var blocChiffre = try ServiceCanalChiffreCrypto.chiffrerAESGCM(
            donneesClaires: Data("Alerte niveau critique".utf8),
            cle: clesIPhone.cleIPhoneVersMac,
            donneesAssociees: ServiceCanalChiffreCrypto.aadDirectionIPhoneVersMac
        )

        // Un attaquant M2 sur le réseau local inverse un bit au milieu du texte chiffré
        let indexMilieu = blocChiffre.count / 2
        blocChiffre[indexMilieu] ^= 0x01

        #expect(throws: ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue) {
            _ = try serviceCanalMac.dechiffrerMessageDepuisIPhone(blocChiffre)
        }
    }

    // MARK: - 3. Test des deux clés directionnelles HKDF contre la réflexion (CHOIX_CRYPTO.md §3.2 et §6)

    @Test("Séparation des clés HKDF par sens : un message chiffré avec la clé de l'autre sens est refusé")
    func rejetMessageChiffreAvecCleAutreSens() throws {
        let (serviceAppairage, cleIdentiteIPhone, cleIdentiteMac) = try effectuerAppairagePrealable()
        let serviceCanalMac = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)

        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let messageECDH = try creerMessageECDHIPhoneValide(
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePriveeIdentiteIPhone: cleIdentiteIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac
        )
        _ = try serviceCanalMac.etablirCanalDepuisMessageIPhone(messageECDH)

        // Le Mac chiffre un message avec sa clé d'émission (Mac -> iPhone)
        let blocEmisParMac = try serviceCanalMac.chiffrerMessageVersIPhone(Data("Message du Mac".utf8))

        // Un attaquant M2 sur le réseau capture ce message et le renvoie au Mac (attaque par réflexion).
        // Comme le Mac déchiffre les messages entrants avec `cleIPhoneVersMac` (!= `cleMacVersIPhone`),
        // le déchiffrement échoue immédiatement.
        #expect(throws: ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue) {
            _ = try serviceCanalMac.dechiffrerMessageDepuisIPhone(blocEmisParMac)
        }
    }

    // MARK: - 4. Tests contre S1 et E2 lors de l'établissement du canal ECDH

    @Test("Contre E2 : Impossible d'ouvrir un canal chiffré si aucun iPhone n'est appairé et confirmé")
    func rejetOuvertureCanalSansAppairage() throws {
        let serviceAppairageNonAppaire = ServiceAppairageCrypto()
        let serviceCanalMac = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairageNonAppaire)

        let cleEph = P256.KeyAgreement.PrivateKey()
        let cleFausseIdentite = P256.Signing.PrivateKey()
        let signature = try cleFausseIdentite.signature(for: cleEph.publicKey.rawRepresentation)

        let message = MessageEchangeECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEph.publicKey.rawRepresentation,
            signatureIdentiteIPhone: signature.rawRepresentation
        )

        #expect(throws: ErreurCanalChiffreCrypto.pairNonAppaire) {
            _ = try serviceCanalMac.etablirCanalDepuisMessageIPhone(message)
        }
        #expect(!serviceCanalMac.estOuvert)
    }

    @Test("Contre S1 : Rejet d'une clé ECDH éphémère signée par un attaquant (Homme du milieu)")
    func rejetCleECDHEphemeralSigneeParAttaquant() throws {
        let (serviceAppairage, _, cleIdentiteMac) = try effectuerAppairagePrealable()
        let serviceCanalMac = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)

        // Un attaquant M2 génère sa propre clé ECDH éphémère et la signe avec sa propre clé ECDSA
        let cleEphAttaquant = P256.KeyAgreement.PrivateKey()
        let cleIdentiteAttaquant = P256.Signing.PrivateKey()
        let donnees = ServiceCanalChiffreCrypto.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphAttaquant.publicKey.rawRepresentation,
            clePubliqueIdentiteMacBrute: cleIdentiteMac.rawRepresentation
        )
        let signatureAttaquant = try cleIdentiteAttaquant.signature(for: donnees)

        let messageAttaquant = MessageEchangeECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphAttaquant.publicKey.rawRepresentation,
            signatureIdentiteIPhone: signatureAttaquant.rawRepresentation
        )

        #expect(throws: ErreurCanalChiffreCrypto.signatureEphemeralInvalide) {
            _ = try serviceCanalMac.etablirCanalDepuisMessageIPhone(messageAttaquant)
        }
        #expect(!serviceCanalMac.estOuvert)
        if case .verrouille = serviceCanalMac.etat {
            // Comportement attendu : échec en sécurité
        } else {
            Issue.record("Le canal devrait être verrouillé après une signature ECDH invalide")
        }
    }

    // MARK: - 5. Test d'intégration ViewModel : Réception d'alerte chiffrée et purge en RAM (MAC-3, MAC-7, I4)

    @Test("Intégration CentraleMacViewModel : réception d'une alerte chiffrée AES-GCM et purge complète en RAM")
    func receptionAlerteChiffreeEtPurgeViewModel() throws {
        let (serviceAppairage, cleIdentiteIPhone, cleIdentiteMac) = try effectuerAppairagePrealable()
        let fauxReseau = FauxServiceReceptionAlertes()
        let viewModel = CentraleMacViewModel(
            serviceReception: fauxReseau,
            serviceAppairage: serviceAppairage
        )

        // 1. Ouverture du canal chiffré via le ViewModel
        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let messageECDH = try creerMessageECDHIPhoneValide(
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePriveeIdentiteIPhone: cleIdentiteIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac
        )
        guard let reponseMac = viewModel.ouvrirCanalChiffre(messageECDH) else {
            Issue.record("L'ouverture du canal chiffré aurait dû réussir")
            return
        }

        let clesIPhone = try ServiceCanalChiffreCrypto.finaliserCanalCoteIPhone(
            reponseMac: reponseMac,
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePubliqueIdentiteMac: cleIdentiteMac,
            clePubliqueIdentiteIPhoneBrute: cleIdentiteIPhone.publicKey.rawRepresentation
        )

        // 2. L'iPhone encode une Alerte en JSON (ISO-8601) et la chiffre en AES-256-GCM
        let alerte = Alerte(
            niveau: .critique,
            idHache: Data(repeating: 0xCD, count: Alerte.tailleAttendueIdHache),
            balayagesRefs: [UUID()]
        )
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        let jsonClair = try encodeur.encode(alerte)

        let blocAESGCM = try ServiceCanalChiffreCrypto.chiffrerAESGCM(
            donneesClaires: jsonClair,
            cle: clesIPhone.cleIPhoneVersMac,
            donneesAssociees: ServiceCanalChiffreCrypto.aadDirectionIPhoneVersMac
        )

        // 3. Le ViewModel Mac déchiffre et enregistre l'alerte en mémoire
        let accepte = viewModel.recevoirAlerteChiffree(blocAESGCM)
        #expect(accepte)
        #expect(viewModel.alertesRecues.count == 1)
        #expect(viewModel.alertesRecues.first?.id == alerte.id)

        // 4. Purge de fin de séance (MAC-7 / I4) : efface l'historique, les clés du canal et les clés d'appairage
        viewModel.purgerHistoriqueSession()
        #expect(viewModel.alertesRecues.isEmpty)
        #expect(viewModel.etatCanalChiffre == .ferme)
        #expect(viewModel.etatAppairage == .nonAppaire)

        // Toute tentative de déchiffrer l'alerte après la purge échoue car les clés de session ont été détruites
        let accepteApresPurge = viewModel.recevoirAlerteChiffree(blocAESGCM)
        #expect(!accepteApresPurge)
    }
}
#endif
