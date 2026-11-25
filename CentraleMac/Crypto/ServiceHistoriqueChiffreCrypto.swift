#if canImport(CryptoKit)
import Foundation
import CryptoKit

// MARK: - Modèles et erreurs du coffre d'historique chiffré en RAM (MAC-5, étiquette `crypto` -> relecture Aïda)

/// Erreurs cryptographiques liées au stockage chiffré de l'historique sur la centrale Mac (`MAC-5`).
///
/// Menaces STRIDE couvertes :
/// - `I4` / `RR5` : Protection des alertes en mémoire vive par chiffrement `AES-256-GCM` et effacement cryptographique (*crypto-shredding*) lors de la purge.
/// - `T3` / `T4` : Détection de toute corruption ou altération d'une entrée de l'historique via le tag d'authentification GCM.
public enum ErreurHistoriqueChiffreCrypto: Error, Equatable, Sendable {
    /// La clé symétrique de l'historique a été purgée ou le coffre est verrouillé en sécurité.
    case coffreVerrouilleOuPurge
    /// La sérialisation ou la désérialisation JSON de l'alerte a échoué.
    case encodageOuDecodageEchoue
    /// Le chiffrement ou la vérification du tag d'intégrité `AES-256-GCM` a échoué (`T3`, `T4`).
    case integriteAESGCMEchouee
}

/// Entrée individuelle stockée sous forme chiffrée dans la mémoire vive de la centrale Mac (`MAC-5`).
///
/// Aucun champ métier (`niveau`, `idHache`, `balayagesRefs`, `date`) n'est conservé en clair :
/// seul `blocAESGCM` (`nonce 12 o || JSON chiffré || tag GCM 16 o`) réside en mémoire.
public struct EntreeHistoriqueChiffree: Equatable, Sendable {
    /// Identifiant unique de l'événement (utilisé uniquement pour la déduplication et comme donnée associée AAD du bloc GCM).
    public let idAlerte: UUID
    /// Bloc combiné `AES-256-GCM` (`nonce 12 octets || texte chiffré || tag 16 octets`).
    public let blocAESGCM: Data

    public init(idAlerte: UUID, blocAESGCM: Data) {
        self.idAlerte = idAlerte
        self.blocAESGCM = blocAESGCM
    }
}

// MARK: - Protocole du service d'historique chiffré (`CLAUDE.md` §7)

/// Contrat abstrait du coffre d'historique chiffré en mémoire vive sur la centrale Mac (`MAC-5`).
public protocol ServiceHistoriqueChiffreCryptoProtocol: AnyObject {
    /// Nombre d'entrées chiffrées actuellement présentes dans le coffre en RAM.
    var nombreEntreesChiffrees: Int { get }
    /// Indique si le coffre dispose d'une clé `AES-256` active en mémoire.
    var possedeCleActive: Bool { get }
    /// Accès en lecture aux entrées chiffrées brutes (permet aux tests unitaires de vérifier l'absence de texte en clair).
    var entreesChiffreesBrutes: [EntreeHistoriqueChiffree] { get }

    /// Chiffre une `Alerte` en `AES-256-GCM` avec un nonce aléatoire CryptoKit et l'insère en tête de l'historique en RAM.
    ///
    /// - Parameter alerte: L'alerte validée à chiffrer et stocker.
    /// - Returns: `true` si l'alerte a été ajoutée, `false` si son `id` était déjà présent (déduplication).
    /// - Throws: `ErreurHistoriqueChiffreCrypto` si l'alerte est invalide ou si le chiffrement échoue.
    @discardableResult
    func ajouterAlerteChiffree(_ alerte: Alerte) throws -> Bool

    /// Déchiffre et vérifie l'intégrité (`AES-256-GCM`) de toutes les entrées de l'historique pour l'affichage.
    ///
    /// Conformément au principe « Échouer en sécurité » (`CLAUDE.md` §6), si une seule entrée a été altérée (`T3`/`T4`),
    /// le coffre se verrouille, détruit sa clé et lève `ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee`.
    ///
    /// - Returns: La liste des `Alerte` déchiffrées, de la plus récente à la plus ancienne.
    /// - Throws: `ErreurHistoriqueChiffreCrypto` en cas d'altération d'un octet ou de clé absente.
    func lireAlertesDechiffrees() throws -> [Alerte]

    /// Déchiffre un bloc `EntreeHistoriqueChiffree` avec la clé active du coffre.
    ///
    /// - Parameter entree: L'entrée chiffrée à vérifier et ouvrir.
    /// - Returns: L'`Alerte` déchiffrée.
    /// - Throws: `ErreurHistoriqueChiffreCrypto` si la clé a été purgée ou si le tag GCM est invalide.
    func dechiffrerEntree(_ entree: EntreeHistoriqueChiffree) throws -> Alerte

    /// Détruit la clé `AES-256` en cours et vide toutes les entrées chiffrées en RAM (*crypto-shredding*, `MAC-7` / `I4`).
    ///
    /// - Parameter regenererNouvelleCle: Si `true` (par défaut lors d'une purge en cours de séance), génère une nouvelle clé
    ///   vierge après destruction de l'ancienne ; si `false` (fermeture de l'application), laisse la clé à `nil`.
    func purgerHistoriqueEtCle(regenererNouvelleCle: Bool)
}

// MARK: - Implémentation CryptoKit de l'historique chiffré (MAC-5)

/// Implémentation du coffre d'historique chiffré en mémoire vive avec `AES-256-GCM` (`MAC-5`).
///
/// Conforme à `CLAUDE.md` (§6 et §7) et `docs/securite/CHOIX_CRYPTO.md` :
/// - **CryptoKit uniquement** : `SymmetricKey(size: .bits256)` et `AES.GCM`.
/// - **Nonce aléatoire** : généré automatiquement par `AES.GCM.seal` à chaque entrée (jamais de nonce fixe).
/// - **Données associées authentifiées (AAD)** : chaque bloc `AES-GCM` est lié cryptographiquement au préfixe
///   `"antitracker-historique-mac-v1"` et aux 16 octets de l'`idAlerte`, empêchant de permuter le chiffré d'une entrée avec une autre.
/// - **Effacement cryptographique (*Crypto-shredding*, `I4`)** : lors de la purge (`MAC-7`), la clé `SymmetricKey` de 256 bits
///   est détruite, rendant définitivement indéchiffrable tout résidu mémoire.
public final class ServiceHistoriqueChiffreCrypto: ServiceHistoriqueChiffreCryptoProtocol {
    /// Plafond de sécurité du nombre d'entrées gardées dans le coffre en RAM pendant une séance (`D2`).
    public static let nombreMaxEntreesEnMemoire = 500
    /// Préfixe de séparation de domaine pour les données associées authentifiées (AAD) d'AES-GCM.
    public static let prefixeAADHistorique = "antitracker-historique-mac-v1"

    /// Clé symétrique AES-256 éphémère de l'historique (uniquement en RAM, jamais écrite sur disque ni Keychain).
    private var cleHistoriqueRAM: SymmetricKey?
    /// Liste ordonnée des entrées chiffrées (de la plus récente à la plus ancienne).
    private var entreesChiffrees: [EntreeHistoriqueChiffree] = []

    public var nombreEntreesChiffrees: Int {
        entreesChiffrees.count
    }

    public var possedeCleActive: Bool {
        cleHistoriqueRAM != nil
    }

    public var entreesChiffreesBrutes: [EntreeHistoriqueChiffree] {
        entreesChiffrees
    }

    /// Initialise le coffre d'historique chiffré en générant une clé `AES-256` aléatoire en RAM via CryptoKit.
    public init() {
        self.cleHistoriqueRAM = SymmetricKey(size: .bits256)
    }

    // MARK: - Chiffrement et ajout en tête d'historique

    @discardableResult
    public func ajouterAlerteChiffree(_ alerte: Alerte) throws -> Bool {
        // 1. Validation préalable du format de l'alerte (`idHache` == 32 octets).
        do {
            try alerte.validerFormat()
        } catch {
            throw ErreurHistoriqueChiffreCrypto.encodageOuDecodageEchoue
        }

        // 2. Si le coffre avait été fermé sans clé, on en génère une neuve en RAM.
        if cleHistoriqueRAM == nil {
            cleHistoriqueRAM = SymmetricKey(size: .bits256)
        }
        guard let cle = cleHistoriqueRAM else {
            throw ErreurHistoriqueChiffreCrypto.coffreVerrouilleOuPurge
        }

        // 3. Déduplication par identifiant d'événement.
        guard !entreesChiffrees.contains(where: { $0.idAlerte == alerte.id }) else {
            return false
        }

        // 4. Sérialisation JSON ISO-8601 de l'alerte.
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        encodeur.outputFormatting = [.sortedKeys]
        let donneesClaires: Data
        do {
            donneesClaires = try encodeur.encode(alerte)
        } catch {
            throw ErreurHistoriqueChiffreCrypto.encodageOuDecodageEchoue
        }

        // 5. Chiffrement AES-256-GCM avec nonce aléatoire généré par CryptoKit et AAD liée à l'UUID de l'alerte.
        let aad = Self.construireAAD(pour: alerte.id)
        let boiteScellee: AES.GCM.SealedBox
        do {
            boiteScellee = try AES.GCM.seal(
                donneesClaires,
                using: cle,
                authenticating: aad
            )
        } catch {
            throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
        }

        guard let blocCombine = boiteScellee.combined else {
            throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
        }

        // 6. Insertion en tête (index 0) et application du plafond de 500 entrées (contre D2).
        let entree = EntreeHistoriqueChiffree(idAlerte: alerte.id, blocAESGCM: blocCombine)
        entreesChiffrees.insert(entree, at: 0)

        if entreesChiffrees.count > Self.nombreMaxEntreesEnMemoire {
            entreesChiffrees.removeLast(entreesChiffrees.count - Self.nombreMaxEntreesEnMemoire)
        }

        return true
    }

    // MARK: - Lecture et vérification d'intégrité AES-256-GCM

    public func lireAlertesDechiffrees() throws -> [Alerte] {
        if entreesChiffrees.isEmpty {
            return []
        }
        guard cleHistoriqueRAM != nil else {
            throw ErreurHistoriqueChiffreCrypto.coffreVerrouilleOuPurge
        }

        var resultat: [Alerte] = []
        resultat.reserveCapacity(entreesChiffrees.count)

        for entree in entreesChiffrees {
            do {
                let alerte = try dechiffrerEntree(entree)
                resultat.append(alerte)
            } catch {
                // Principe « Échouer en sécurité » (CLAUDE.md §6, STRIDE T3) :
                // toute corruption d'une entrée verrouille et vide le coffre.
                verrouillerEnSecurite()
                throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
            }
        }

        return resultat
    }

    public func dechiffrerEntree(_ entree: EntreeHistoriqueChiffree) throws -> Alerte {
        guard let cle = cleHistoriqueRAM else {
            throw ErreurHistoriqueChiffreCrypto.coffreVerrouilleOuPurge
        }

        let boiteScellee: AES.GCM.SealedBox
        do {
            boiteScellee = try AES.GCM.SealedBox(combined: entree.blocAESGCM)
        } catch {
            throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
        }

        let aad = Self.construireAAD(pour: entree.idAlerte)
        let donneesClaires: Data
        do {
            donneesClaires = try AES.GCM.open(
                boiteScellee,
                using: cle,
                authenticating: aad
            )
        } catch {
            throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
        }

        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        let alerte: Alerte
        do {
            alerte = try decodeur.decode(Alerte.self, from: donneesClaires)
            try alerte.validerFormat()
        } catch {
            throw ErreurHistoriqueChiffreCrypto.encodageOuDecodageEchoue
        }

        // Vérifie que l'identifiant interne déchiffré correspond bien à l'identifiant de l'enveloppe AAD.
        guard alerte.id == entree.idAlerte else {
            throw ErreurHistoriqueChiffreCrypto.integriteAESGCMEchouee
        }

        return alerte
    }

    // MARK: - Purge cryptographique (*Crypto-shredding*, MAC-5 / MAC-7 / I4)

    public func purgerHistoriqueEtCle(regenererNouvelleCle: Bool = true) {
        entreesChiffrees.removeAll(keepingCapacity: false)
        // Destruction de l'ancienne clé AES-256 : tout ancien bloc chiffré devient mathématiquement indéchiffrable.
        cleHistoriqueRAM = regenererNouvelleCle ? SymmetricKey(size: .bits256) : nil
    }

    // MARK: - Aides internes

    /// Construit les données associées authentifiées (AAD) liant un bloc AES-GCM à son `UUID` d'alerte.
    public static func construireAAD(pour idAlerte: UUID) -> Data {
        var aad = Data(prefixeAADHistorique.utf8)
        withUnsafeBytes(of: idAlerte.uuid) { octetsUUID in
            aad.append(contentsOf: octetsUUID)
        }
        return aad
    }

    /// Efface les entrées et détruit la clé en cas de détection d'altération mémoire (`T3`/`T4`).
    private func verrouillerEnSecurite() {
        entreesChiffrees.removeAll(keepingCapacity: false)
        cleHistoriqueRAM = nil
    }

    #if DEBUG
    /// Méthode réservée aux tests unitaires (`QA-3` / `MAC-5`) pour simuler l'altération d'un octet en mémoire (`T3`/`T4`).
    internal func remplacerEntreePourTest(a index: Int, par nouvelleEntree: EntreeHistoriqueChiffree) {
        guard entreesChiffrees.indices.contains(index) else { return }
        entreesChiffrees[index] = nouvelleEntree
    }
    #endif
}
#endif
