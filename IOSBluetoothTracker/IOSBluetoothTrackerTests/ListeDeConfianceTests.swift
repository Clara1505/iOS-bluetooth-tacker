import Foundation
import Testing
// Adapter le nom du module au nom de la cible Xcode une fois créée (IOS-1).
@testable import TrackerBluetooth

/// Tests de la logique pure de la liste de confiance (sans Keychain ni Secure Enclave).
/// Les tests de signature et d'authentification se font sur iPhone, voir le plan de tests à part.
struct ListeDeConfianceTests {

    // MARK: - Données signées

    @Test("Les données signées commencent par le libellé et contiennent la version en big-endian")
    func donneesSigneesContiennentLibelleEtVersion() {
        let bloc = Data([0x01, 0x02, 0x03])
        let donnees = DonneesSignees.construire(version: 258, bloc: bloc)

        let longueurLibelle = DonneesSignees.libelle.count
        #expect(donnees.prefix(longueurLibelle) == DonneesSignees.libelle)

        // 258 = 0x0102 : sur 8 octets big-endian, les deux derniers octets valent 0x01 0x02.
        let versionOctets = donnees.dropFirst(longueurLibelle).prefix(8)
        #expect(Array(versionOctets) == [0, 0, 0, 0, 0, 0, 0x01, 0x02])

        #expect(donnees.suffix(bloc.count) == bloc)
    }

    @Test("Une version différente produit des données signées différentes")
    func versionDifferenteChangeLesDonnees() {
        let bloc = Data([0xAA, 0xBB])
        #expect(DonneesSignees.construire(version: 1, bloc: bloc) != DonneesSignees.construire(version: 2, bloc: bloc))
    }

    // MARK: - Règle de version

    @Test("Une version plus ancienne que la version mémorisée est refusée")
    func versionPerimeeEstRefusee() {
        #expect(throws: ErreurListeDeConfiance.versionPerimee) {
            try DonneesSignees.accepterVersion(lue: 3, memorisee: 5)
        }
    }

    @Test("Une version identique n'est pas à mémoriser à nouveau")
    func versionIdentiqueNeDoitPasEtreMemorisee() throws {
        let doitMemoriser = try DonneesSignees.accepterVersion(lue: 5, memorisee: 5)
        #expect(doitMemoriser == false)
    }

    @Test("Une version plus récente est acceptée et doit être mémorisée")
    func versionPlusRecenteDoitEtreMemorisee() throws {
        let doitMemoriser = try DonneesSignees.accepterVersion(lue: 6, memorisee: 5)
        #expect(doitMemoriser == true)
    }

    @Test("Sans version mémorisée (0), la première version est acceptée")
    func premiereVersionEstAcceptee() throws {
        let doitMemoriser = try DonneesSignees.accepterVersion(lue: 1, memorisee: 0)
        #expect(doitMemoriser == true)
    }

    // MARK: - Historique

    @Test("L'historique ne conserve que les 20 dernières entrées")
    func historiqueLimiteA20Entrees() {
        var contenu = ContenuListe()
        for index in 0..<25 {
            contenu.ajouterHistorique(
                EntreeHistorique(
                    date: Date(timeIntervalSince1970: TimeInterval(index)),
                    action: .ajout,
                    nomAppareil: "appareil \(index)",
                    mode: .faceID
                )
            )
        }

        #expect(contenu.historique.count == ContenuListe.tailleMaxHistorique)
        #expect(contenu.historique.first?.nomAppareil == "appareil 5")
        #expect(contenu.historique.last?.nomAppareil == "appareil 24")
    }

    // MARK: - Encodage

    @Test("Le contenu de la liste survit à un aller-retour JSON")
    func contenuSurvitAEncodage() throws {
        var contenu = ContenuListe()
        contenu.appareils.append(
            AppareilDeConfiance(idHache: Data([0x10, 0x20]), nom: "Sac", ajouteLe: Date(timeIntervalSince1970: 1_000))
        )
        contenu.ajouterHistorique(
            EntreeHistorique(
                date: Date(timeIntervalSince1970: 1_000),
                action: .ajout,
                nomAppareil: "Sac",
                mode: .code
            )
        )

        let donnees = try JSONEncoder().encode(contenu)
        let relu = try JSONDecoder().decode(ContenuListe.self, from: donnees)
        #expect(relu == contenu)
    }

    // MARK: - Noms d'appareils

    @Test("Un nom simple sans accent est accepté")
    func nomSimpleEstAccepte() throws {
        let nom = try NomAppareil("Sac")
        #expect(nom.valeur == "Sac")
    }

    @Test("Un nom avec des chiffres et des espaces est accepté")
    func nomAvecChiffresEstAccepte() throws {
        let nom = try NomAppareil("Sac 2 Bleu")
        #expect(nom.valeur == "Sac 2 Bleu")
    }

    @Test("Un nom de 15 caractères est accepté, un de 16 est refusé")
    func longueurMaximaleDeQuinze() throws {
        let accepte = try NomAppareil("ABCDEFGHIJKLMNO")
        #expect(accepte.valeur.count == 15)
        #expect(throws: ErreurNomAppareil.tropLong) {
            try NomAppareil("ABCDEFGHIJKLMNOP")
        }
    }

    @Test("Un accent est refusé")
    func accentEstRefuse() {
        #expect(throws: ErreurNomAppareil.caractereNonAutorise) {
            try NomAppareil("Été")
        }
    }

    @Test("Un accent décomposé (lettre suivie d'un accent combinant) est refusé")
    func accentDecomposeEstRefuse() {
        #expect(throws: ErreurNomAppareil.caractereNonAutorise) {
            try NomAppareil("e\u{0301}t\u{0301}")
        }
    }

    @Test("Un emoji, seul ou dans une séquence, est refusé")
    func emojiEstRefuse() {
        #expect(throws: ErreurNomAppareil.caractereNonAutorise) {
            try NomAppareil("🎒 Sac")
        }
        #expect(throws: ErreurNomAppareil.caractereNonAutorise) {
            try NomAppareil("👨‍👩‍👧")
        }
    }

    @Test("La ponctuation ASCII est refusée")
    func ponctuationEstRefusee() {
        #expect(throws: ErreurNomAppareil.caractereNonAutorise) {
            try NomAppareil("a#b")
        }
    }

    @Test("Un nom vide ou composé d'espaces est refusé, et les espaces de bord sont retirés")
    func nomVideEtEspacesDeBord() throws {
        #expect(throws: ErreurNomAppareil.vide) {
            try NomAppareil("   ")
        }
        let nom = try NomAppareil("  Sac  ")
        #expect(nom.valeur == "Sac")
    }
}
