#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-7 : Purge de l'historique et des clés de la centrale en fin de séance (I4, C3)")
struct PurgeFinSeanceTests {

    // MARK: - Aide d'initialisation d'une séance active complète (MAC-1 + MAC-2 + MAC-3 + MAC-4)

    /// Monte une séance complète avec serveur démarré, appairage QR confirmé, canal chiffré AES-256-GCM ouvert
    /// et événements signés enregistrés en RAM.
    private func monterSeanceActiveComplete() throws -> (
        viewModel: CentraleMacViewModel,
        fauxReseau: FauxServiceReceptionAlertes,
        serviceAppairage: ServiceAppairageCrypto,
        serviceCanal: ServiceCanalChiffreCrypto,
        serviceEvenements: ServiceEvenementsSignesCrypto,
        blocEvenementChiffreValide: Data
    ) {
        let fauxReseau = FauxServiceReceptionAlertes()
        let serviceAppairage = ServiceAppairageCrypto()
        let serviceCanal = ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)
        let serviceEvenements = ServiceEvenementsSignesCrypto(serviceAppairage: serviceAppairage)

        let viewModel = CentraleMacViewModel(
            serviceReception: fauxReseau,
            serviceAppairage: serviceAppairage,
            serviceCanalChiffre: serviceCanal,
            serviceEvenementsSignes: serviceEvenements
        )

        // 1. Démarrage du serveur TCP (MAC-1)
        viewModel.demarrerCentrale()
        #expect(viewModel.etatServeur == .enEcoute(port: 54321))

        // 2. Appairage par QR code et confirmation d'empreinte (MAC-2)
        viewModel.genererQRCodeAppairage()
        guard case .qrCodeAffiche(let chargeQR, _) = viewModel.etatAppairage else {
            throw ErreurAppairageCrypto.etatAppairageInvalide
        }

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
        _ = viewModel.recevoirDemandeAppairage(demande)
        viewModel.confirmerAppairage()

        guard let clePubliqueMac = serviceAppairage.clePubliqueIdentiteMac else {
            throw ErreurAppairageCrypto.etatAppairageInvalide
        }

        // 3. Ouverture du canal chiffré ECDH + HKDF + AES-256-GCM (MAC-3)
        let cleEphIPhone = P256.KeyAgreement.PrivateKey()
        let donneesECDH = ServiceCanalChiffreCrypto.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
            clePubliqueIdentiteMacBrute: clePubliqueMac.rawRepresentation
        )
        let sigECDH = try clePriveeIPhone.signature(for: donneesECDH)
        let messageECDH = MessageEchangeECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: cleEphIPhone.publicKey.rawRepresentation,
            signatureIdentiteIPhone: sigECDH.rawRepresentation
        )

        guard let reponseECDHMac = viewModel.ouvrirCanalChiffre(messageECDH) else {
            throw ErreurCanalChiffreCrypto.canalNonOuvert
        }
        let clesSessionIPhone = try ServiceCanalChiffreCrypto.finaliserCanalCoteIPhone(
            reponseMac: reponseECDHMac,
            clePriveeEphemeralIPhone: cleEphIPhone,
            clePubliqueIdentiteMac: clePubliqueMac,
            clePubliqueIdentiteIPhoneBrute: clePubliqueIPhoneBrute
        )

        // 4. Réception d'un événement signé et chiffré (MAC-4)
        let maintenant = Date()
        let alerte = Alerte(
            niveau: .critique,
            idHache: Data(repeating: 0x99, count: Alerte.tailleAttendueIdHache),
            balayagesRefs: [UUID()],
            date: maintenant
        )
        let evenement1 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerte,
            compteur: 1,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        let blocChiffre1 = try ServiceEvenementsSignesCrypto.encoderEtChiffrerEvenementCoteIPhone(
            evenement: evenement1,
            cleSessionIPhoneVersMac: clesSessionIPhone.cleIPhoneVersMac
        )
        let accepte = viewModel.recevoirEvenementSigneEtChiffre(blocChiffre1, dateReferenceMac: maintenant)
        #expect(accepte)

        // Préparation d'un second événement signé (compteur = 2) pour tester son rejet après purge
        let evenement2 = try ServiceEvenementsSignesCrypto.creerEvenementSigne(
            alerte: alerte,
            compteur: 2,
            horodatage: maintenant,
            signataire: signataireIPhone
        )
        let blocChiffre2 = try ServiceEvenementsSignesCrypto.encoderEtChiffrerEvenementCoteIPhone(
            evenement: evenement2,
            cleSessionIPhoneVersMac: clesSessionIPhone.cleIPhoneVersMac
        )

        return (viewModel, fauxReseau, serviceAppairage, serviceCanal, serviceEvenements, blocChiffre2)
    }

    // MARK: - 1. Test de purge manuelle par l'utilisateur (STRIDE I4 : vérifier qu'aucune donnée ne reste)

    @Test("Contre I4 : La purge utilisateur efface l'historique, l'état anti-rejeu, les clés de session et d'appairage")
    func purgeManuelleUtilisateurEffaceToutesLesDonneesEnRAM() throws {
        let (viewModel, _, serviceAppairage, serviceCanal, serviceEvenements, blocChiffreSuivant) =
            try monterSeanceActiveComplete()

        // Avant la purge : la session contient des alertes, des clés et un compteur anti-rejeu > 0
        #expect(!viewModel.estSessionTotalementPurgee)
        #expect(viewModel.alertesRecues.count == 1)
        #expect(serviceAppairage.estAppaire)
        #expect(serviceAppairage.clePubliqueIPhoneAppaire != nil)
        #expect(serviceAppairage.clePubliqueIdentiteMac != nil)
        #expect(serviceCanal.estOuvert)
        #expect(serviceEvenements.dernierCompteurAccepte == 1)
        #expect(serviceEvenements.nombreNoncesVus == 1)

        // Action utilisateur : clic sur "Purger la session et les clés (RAM)"
        viewModel.purgerHistoriqueSession()

        // Vérification exhaustive post-purge (test prévu par STRIDE.md pour I4)
        #expect(viewModel.estSessionTotalementPurgee)
        #expect(viewModel.alertesRecues.isEmpty)
        #expect(viewModel.dernierCompteurAntiRejeu == 0)
        #expect(serviceEvenements.dernierCompteurAccepte == 0)
        #expect(serviceEvenements.nombreNoncesVus == 0)
        #expect(!serviceCanal.estOuvert)
        #expect(viewModel.etatCanalChiffre == .ferme)
        #expect(!serviceAppairage.estAppaire)
        #expect(serviceAppairage.clePubliqueIPhoneAppaire == nil)
        #expect(serviceAppairage.clePubliqueIdentiteMac == nil)
        #expect(viewModel.etatAppairage == .nonAppaire)
        #expect(viewModel.nombrePurgesEffectuees == 1)
        #expect(viewModel.dernierMotifPurge == .actionUtilisateur)
        #expect(viewModel.dateDernierePurge != nil)

        // Toute tentative de pousser l'événement suivant chiffré avec les anciennes clés est rejetée
        #expect(!viewModel.recevoirEvenementSigneEtChiffre(blocChiffreSuivant))
        #expect(viewModel.alertesRecues.isEmpty)
    }

    // MARK: - 2. Test de purge automatique à la fermeture de la fenêtre ou de l'application (C3, I4)

    @Test("Contre I4 et C3 : La fermeture de l'app déclenche automatiquement la purge complète et coupe l'écouteur TCP")
    func purgeAutomatiqueFermetureApplicationEtArretServeur() throws {
        let (viewModel, fauxReseau, serviceAppairage, serviceCanal, serviceEvenements, _) =
            try monterSeanceActiveComplete()

        #expect(!viewModel.estSessionTotalementPurgee)
        #expect(viewModel.etatServeur == .enEcoute(port: 54321))
        let appelsArreterAvant = fauxReseau.nombreAppelsArreter

        // Simulation de la fermeture de la fenêtre (.onDisappear) ou de l'application (willTerminateNotification)
        viewModel.purgerLorsDeLaFermeture()

        // 1. Toutes les données et clés en RAM sont purgées
        #expect(viewModel.estSessionTotalementPurgee)
        #expect(!serviceAppairage.estAppaire)
        #expect(!serviceCanal.estOuvert)
        #expect(serviceEvenements.dernierCompteurAccepte == 0)
        #expect(serviceEvenements.nombreNoncesVus == 0)

        // 2. Le serveur TCP a bien été arrêté automatiquement
        #expect(fauxReseau.nombreAppelsArreter == appelsArreterAvant + 1)
        #expect(viewModel.etatServeur == .arrete)

        // 3. Le motif enregistré indique bien une fermeture automatique de l'application
        #expect(viewModel.dernierMotifPurge == .fermetureApplication)
        #expect(viewModel.nombrePurgesEffectuees == 1)
    }
}
#endif
