import CryptoKit
import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Magasin de clé en mémoire pour les tests.
private final class MagasinEnMemoire: MagasinCle {
    var octets: Data?
    private(set) var ecritures = 0

    init(octets: Data? = nil) {
        self.octets = octets
    }

    func lire() throws -> Data? { octets }

    func ecrire(_ octets: Data) throws {
        ecritures += 1
        self.octets = octets
    }

    func supprimer() throws { octets = nil }
}

@Suite("Hachage des identifiants (TRU-6, I5)")
struct HachageTests {

    private let identifiant = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F") ?? UUID()

    @Test("Vecteur public RFC 4231, cas 2 : l'algorithme est bien HMAC-SHA256")
    func vecteurRFC4231() {
        let cle = SymmetricKey(data: Data("Jefe".utf8))
        let resultat = HacheurHMAC.calculer(cle: cle, donnees: Data("what do ya want for nothing?".utf8))
        let attendu = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

        #expect(resultat.map { String(format: "%02x", $0) }.joined() == attendu)
    }

    @Test("Le haché fait 32 octets")
    func tailleDuHache() throws {
        let hacheur = try HacheurHMAC(magasin: MagasinEnMemoire())

        #expect(hacheur.hacher(identifiant).count == 32)
    }

    @Test("Même identifiant et même clé : même haché ; autre identifiant : autre haché")
    func determinismeEtDifference() throws {
        let hacheur = try HacheurHMAC(magasin: MagasinEnMemoire())

        #expect(hacheur.hacher(identifiant) == hacheur.hacher(identifiant))
        #expect(hacheur.hacher(identifiant) != hacheur.hacher(UUID()))
    }

    @Test("La clé est stable : deux hacheurs sur le même magasin donnent le même haché")
    func cleStable() throws {
        let magasin = MagasinEnMemoire()
        let premier = try HacheurHMAC(magasin: magasin)
        let second = try HacheurHMAC(magasin: magasin)

        #expect(premier.hacher(identifiant) == second.hacher(identifiant))
    }

    @Test("La clé n'est créée qu'une fois")
    func cleCreeeUneSeuleFois() throws {
        let magasin = MagasinEnMemoire()

        _ = try HacheurHMAC(magasin: magasin)
        _ = try HacheurHMAC(magasin: magasin)

        #expect(magasin.ecritures == 1)
    }

    @Test("Deux clés différentes donnent des hachés différents")
    func clesDifferentes() throws {
        let un = try HacheurHMAC(magasin: MagasinEnMemoire())
        let deux = try HacheurHMAC(magasin: MagasinEnMemoire())

        #expect(un.hacher(identifiant) != deux.hacher(identifiant))
    }

    @Test("Le haché n'est pas un SHA-256 simple de l'identifiant")
    func pasUnSHA256Simple() throws {
        let hacheur = try HacheurHMAC(magasin: MagasinEnMemoire())
        let octets = withUnsafeBytes(of: identifiant.uuid) { Data($0) }

        #expect(hacheur.hacher(identifiant) != Data(SHA256.hash(data: octets)))
    }

    @Test("Une clé de mauvaise taille est refusée, pas remplacée")
    func cleDeMauvaiseTaille() {
        let magasin = MagasinEnMemoire(octets: Data([1, 2, 3]))

        #expect(throws: ErreurHachage.cleInvalide) {
            try HacheurHMAC(magasin: magasin)
        }
        #expect(magasin.ecritures == 0)
    }
}

@Suite("Purge à 72 h (TRU-6, I5)")
struct PurgeTests {

    private let maintenant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Une donnée de 71 h 59 est conservée")
    func justeAvantLeSeuil() {
        let collecte = maintenant - (72 * 3600 - 60)

        #expect(PolitiquePurge.estExpire(collecteLe: collecte, maintenant: maintenant) == false)
    }

    @Test("Une donnée de 72 h exactement est supprimée")
    func auSeuil() {
        let collecte = maintenant - 72 * 3600

        #expect(PolitiquePurge.estExpire(collecteLe: collecte, maintenant: maintenant))
    }

    @Test("Une donnée de plus de 72 h est supprimée")
    func auDessusDuSeuil() {
        let collecte = maintenant - 73 * 3600

        #expect(PolitiquePurge.estExpire(collecteLe: collecte, maintenant: maintenant))
    }

    @Test("Une date de collecte dans le futur (horloge reculée) est supprimée")
    func dateDansLeFutur() {
        #expect(PolitiquePurge.estExpire(collecteLe: maintenant + 60, maintenant: maintenant))
    }

    @Test("La purge ne garde que les données récentes")
    func purgerFiltre() {
        let dates = [maintenant - 3600, maintenant - 80 * 3600, maintenant - 71 * 3600]

        let restantes = PolitiquePurge.purger(dates, dateCollecte: { $0 }, maintenant: maintenant)

        #expect(restantes == [maintenant - 3600, maintenant - 71 * 3600])
    }

    @Test("Une liste vide reste vide")
    func listeVide() {
        let restantes = PolitiquePurge.purger([Date](), dateCollecte: { $0 }, maintenant: maintenant)

        #expect(restantes.isEmpty)
    }
}

@Suite("Premier lancement (TRU-6, I5)")
struct PremierLancementTests {

    private func defautsNeufs() throws -> UserDefaults {
        let nom = "test-premier-lancement-\(UUID().uuidString)"
        let defauts = try #require(UserDefaults(suiteName: nom))
        defauts.removePersistentDomain(forName: nom)
        return defauts
    }

    @Test("Au premier lancement, les actions s'exécutent et le drapeau est posé")
    func premierLancement() throws {
        let defauts = try defautsNeufs()
        var appels = 0
        let premierLancement = PremierLancement(defauts: defauts, actions: [{ appels += 1 }])

        let execute = try premierLancement.executerSiNecessaire()

        #expect(execute)
        #expect(appels == 1)
        #expect(defauts.bool(forKey: PremierLancement.cleDrapeau))
    }

    @Test("Aux lancements suivants, rien n'est supprimé")
    func lancementsSuivants() throws {
        let defauts = try defautsNeufs()
        var appels = 0
        let premierLancement = PremierLancement(defauts: defauts, actions: [{ appels += 1 }])

        try premierLancement.executerSiNecessaire()
        let execute = try premierLancement.executerSiNecessaire()

        #expect(execute == false)
        #expect(appels == 1)
    }

    @Test("Si une action échoue, le drapeau n'est pas posé et tout est retenté")
    func echecRetente() throws {
        struct Panne: Error {}
        let defauts = try defautsNeufs()
        var doitEchouer = true
        var appels = 0
        let premierLancement = PremierLancement(defauts: defauts, actions: [{
            appels += 1
            if doitEchouer { throw Panne() }
        }])

        #expect(throws: Panne.self) { try premierLancement.executerSiNecessaire() }
        #expect(defauts.bool(forKey: PremierLancement.cleDrapeau) == false)

        doitEchouer = false
        try premierLancement.executerSiNecessaire()

        #expect(appels == 2)
        #expect(defauts.bool(forKey: PremierLancement.cleDrapeau))
    }
}