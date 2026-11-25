#if canImport(Testing) && canImport(CryptoKit)
import Foundation
import CryptoKit
import Testing
@testable import CentraleMacCore

@Suite("Tests unitaires MAC-5 : Historique chiffré AES-256-GCM en RAM, intégrité et crypto-shredding")
struct HistoriqueChiffreTests {

    // MARK: - Aide de création d'alertes fictives (aucune donnée réelle, CLAUDE.md §5)

    private func creerAlerteFictive(
        niveau: NiveauAlerte = .alerte,
        octetIdHache: UInt8 = 0x5A
    ) -> Alerte {
        Alerte(
            niveau: niveau,
            idHache: Data(repeating: octetIdHache, count: Alerte.tailleAttendueIdHache),
            balayagesRefs: [UUID()]
        )
    }

    // MARK: - 1. Chiffrement en RAM et absence de données en clair (I4 / RR5)

    @Test("Les alertes stockées dans le coffre en RAM sont chiffrées en AES-256-GCM et déchiffrées dans l'ordre décroissant")
    func chiffrementEtDechiffrementOrdreDecroissant() throws {
        let coffre = ServiceHistoriqueChiffreCrypto()
        #expect(coffre.possedeCleActive)
        #expect(coffre.nombreEntreesChiffrees == 0)

        let alerte1 = creerAlerteFictive(niveau: .info, octetIdHache: 0xAA)
        let alerte2 = creerAlerteFictive(niveau: .critique, octetIdHache: 0xBB)

        let ajout1 = try coffre.ajouterAlerteChiffree(alerte1)
        let ajout2 = try coffre.ajouterAlerteChiffree(alerte2)
        // Un doublon (même UUID) doit être ignoré
        let ajoutDoublon = try coffre.ajouterAlerteChiffree(alerte2)

        #expect(ajout1)
        #expect(ajout2)
        #expect(!ajoutDoublon)
        #expect(coffre.nombreEntreesChiffrees == 2)

        // Vérifie que le bloc binaire stocké en RAM ne contient pas le condensat idHache en clair
        for entree in coffre.entreesChiffreesBrutes {
            #expect(entree.blocAESGCM.range(of: alerte1.idHache) == nil)
            #expect(entree.blocAESGCM.range(of: alerte2.idHache) == nil)
        }

        // La lecture déchiffre et restitue les alertes de la plus récente à la plus ancienne
        let dechiffrees = try coffre.lireAlertesDechiffrees()
        #expect(dechiffrees.count == 2)
        #expect(dechiffrees[0] == alerte2)
        #expect(dechiffrees[1] == alerte1)
    }

    // MARK: - 2. Détection d'altération d'un octet ou de permutation d'entrées (T3 / T4)

    @Test("Contre T3/T4 : L'altération d'un seul octet dans le coffre en RAM verrouille et vide l'historique en sécurité")
    func rejetEtVerrouillageSurOctetAltere() throws {
        let coffre = ServiceHistoriqueChiffreCrypto()
        let alerte = creerAlerteFictive(niveau: .critique, octetIdHache: 0xCC)
        _ = try coffre.ajouterAlerteChiffree(alerte)

        guard let entreeOriginale = coffre.entreesChiffreesBrutes.first else {
            Issue.record("Une entrée chiffrée devrait être présente")
            return
        }

        // Simulation d'une corruption ou altération d'un bit au milieu du bloc AES-GCM en mémoire
        var blocCorrompu = entreeOriginale.blocAESGCM
        blocCorrompu[blocCorrompu.count / 2] ^= 0x01
        let entreeCorrompue = EntreeHistoriqueChiffree(
            idAlerte: entreeOriginale.idAlerte,
            blocAESGCM: blocCorrompu
        )
        coffre.remplacerEntreePourTest(a: 0, par: entreeCorrompue)

        // La lecture détecte l'échec du tag GCM, lève l'erreur et verrouille/vide le coffre (échec en sécurité)
        #expect(throws: ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee) {
            _ = try coffre.lireAlertesDechiffrees()
        }
        #expect(coffre.nombreEntreesChiffrees == 0)
        #expect(!coffre.possedeCleActive)
    }

    @Test("Contre T3 : La liaison AAD à l'UUID empêche de greffer le bloc chiffré d'une alerte sur un autre UUID")
    func rejetPermutationUUIDSurEntreeChiffree() throws {
        let coffre = ServiceHistoriqueChiffreCrypto()
        let alerte = creerAlerteFictive(niveau: .alerte, octetIdHache: 0xDD)
        _ = try coffre.ajouterAlerteChiffree(alerte)

        guard let entreeOriginale = coffre.entreesChiffreesBrutes.first else {
            Issue.record("Une entrée chiffrée devrait être présente")
            return
        }

        // Remplacement de l'UUID externe sans modifier le bloc AES-GCM : l'AAD ne correspondra plus
        let entreeAvecAutreUUID = EntreeHistoriqueChiffree(
            idAlerte: UUID(),
            blocAESGCM: entreeOriginale.blocAESGCM
        )

        #expect(throws: ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee) {
            _ = try coffre.dechiffrerEntree(entreeAvecAutreUUID)
        }
    }

    // MARK: - 3. Effacement cryptographique (*Crypto-shredding*) lors de la purge (MAC-5 + MAC-7, I4)

    @Test("Contre I4 : Après la purge (crypto-shredding), une ancienne entrée chiffrée capturée en RAM est indéchiffrable")
    func cryptoShreddingRendAnciennesEntreesIndechiffrables() throws {
        let coffre = ServiceHistoriqueChiffreCrypto()
        let alerte = creerAlerteFictive(niveau: .critique, octetIdHache: 0xEE)
        _ = try coffre.ajouterAlerteChiffree(alerte)

        // Un attaquant M5 ayant accès à une empreinte mémoire capture l'entrée chiffrée avant la purge
        guard let entreeCaptureeAvantPurge = coffre.entreesChiffreesBrutes.first else {
            Issue.record("Une entrée chiffrée devrait être présente")
            return
        }

        // Purge de fin de séance : l'ancienne SymmetricKey de 256 bits est détruite
        coffre.purgerHistoriqueEtCle(regenererNouvelleCle: true)
        #expect(coffre.nombreEntreesChiffrees == 0)

        // Même si l'entrée chiffrée avait survécu dans une page mémoire, l'ancienne clé n'existe plus
        #expect(throws: ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee) {
            _ = try coffre.dechiffrerEntree(entreeCaptureeAvantPurge)
        }

        // Purge de fermeture d'application : plus aucune clé active
        coffre.purgerHistoriqueEtCle(regenererNouvelleCle: false)
        #expect(!coffre.possedeCleActive)
        #expect(throws: ErreurHistoriqueChiffreCrypto.coffreVerrouilleOuPurge) {
            _ = try coffre.dechiffrerEntree(entreeCaptureeAvantPurge)
        }
    }
}
#endif
