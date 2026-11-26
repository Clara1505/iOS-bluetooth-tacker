import CryptoKit
import Foundation
import Security

/// Accès à la liste de confiance (TRU-2). Lecture sans authentification, modification signée par la Secure Enclave.
protocol StockageListeDeConfiance {
    /// Lit la liste et vérifie son intégrité. Aucune authentification n'est demandée.
    /// - Returns: le contenu de la liste, vide si le fichier n'existe pas encore (premier lancement).
    /// - Throws: `ErreurListeDeConfiance` si la liste ne peut pas être vérifiée.
    func lire() throws -> ContenuListe

    /// Modifie la liste : ajoute l'entrée d'historique, applique la transformation, rechiffre et signe.
    /// La Secure Enclave demande la biométrie (Face ID ou Touch ID) ou le code de l'iPhone avant de signer.
    /// - Parameters:
    ///   - entree: entrée d'historique correspondant à la modification.
    ///   - transformation: modification à appliquer au contenu.
    /// - Throws: `ErreurListeDeConfiance.authentificationEchouee` si l'utilisateur n'a pas été authentifié.
    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws

    /// Supprime le fichier de la liste et toutes les clés associées (premier lancement après installation).
    func reinitialiser() throws
}

/// Implémentation : AES-GCM pour la confidentialité, signature P-256 dans la Secure Enclave pour l'intégrité.
final class StockageListeDeConfianceSecure: StockageListeDeConfiance {

    /// Structure du fichier sur disque : version, bloc chiffré et signature.
    private struct FichierListe: Codable {
        let version: UInt64
        let bloc: Data
        let signature: Data
    }

    /// Comptes utilisés dans le Keychain.
    private enum Compte: String, CaseIterable {
        case aes = "liste.aes"
        case seBloc = "liste.se.bloc"
        case publique = "liste.se.publique"
        case version = "liste.version"
    }

    /// Service commun à tous les éléments de la liste dans le Keychain.
    private static let service = "fr.tracker.bluetooth.liste"

    private let urlFichier: URL

    /// - Parameter urlFichier: emplacement du fichier de la liste (protection « Complete » appliquée à l'écriture).
    init(urlFichier: URL) {
        self.urlFichier = urlFichier
    }

    // MARK: - API publique

    func lire() throws -> ContenuListe {
        guard FileManager.default.fileExists(atPath: urlFichier.path) else {
            return ContenuListe()
        }

        let fichier: FichierListe
        do {
            let donnees = try Data(contentsOf: urlFichier)
            fichier = try JSONDecoder().decode(FichierListe.self, from: donnees)
        } catch {
            throw ErreurListeDeConfiance.fichierIllisible
        }

        let memorisee = try lireVersionMemorisee()
        let doitMemoriser = try DonneesSignees.accepterVersion(lue: fichier.version, memorisee: memorisee)

        let clePublique = try lireClePublique()
        let donneesSignees = DonneesSignees.construire(version: fichier.version, bloc: fichier.bloc)
        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: fichier.signature),
              clePublique.isValidSignature(signature, for: donneesSignees) else {
            throw ErreurListeDeConfiance.signatureInvalide
        }

        let contenu: ContenuListe
        do {
            let cle = try lireCleAES()
            let boite = try AES.GCM.SealedBox(combined: fichier.bloc)
            let clair = try AES.GCM.open(boite, using: cle)
            contenu = try JSONDecoder().decode(ContenuListe.self, from: clair)
        } catch {
            throw ErreurListeDeConfiance.dechiffrementEchoue
        }

        if doitMemoriser {
            try ecrireVersionMemorisee(fichier.version)
        }
        return contenu
    }

    func modifier(entree: EntreeHistorique, _ transformation: (inout ContenuListe) -> Void) throws {
        var contenu = try lire()
        contenu.ajouterHistorique(entree)
        transformation(&contenu)

        try creerClesSiAbsentes()

        let clair = try JSONEncoder().encode(contenu)
        let cle = try lireCleAES()
        let boite = try AES.GCM.seal(clair, using: cle)
        guard let bloc = boite.combined else {
            throw ErreurListeDeConfiance.erreurSysteme
        }

        let version = try lireVersionMemorisee() + 1
        let donneesSignees = DonneesSignees.construire(version: version, bloc: bloc)

        let clePrivee = try lireClePriveeSE()
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try clePrivee.signature(for: donneesSignees)
        } catch {
            throw ErreurListeDeConfiance.authentificationEchouee
        }

        let fichier = FichierListe(version: version, bloc: bloc, signature: signature.rawRepresentation)
        let donnees = try JSONEncoder().encode(fichier)
        try donnees.write(to: urlFichier, options: [.atomic, .completeFileProtection])
        try ecrireVersionMemorisee(version)
    }

    func reinitialiser() throws {
        if FileManager.default.fileExists(atPath: urlFichier.path) {
            try FileManager.default.removeItem(at: urlFichier)
        }
        for compte in Compte.allCases {
            try supprimerElement(compte)
        }
    }

    // MARK: - Clés

    /// Crée la clé AES et la clé de signature Secure Enclave si elles n'existent pas encore.
    private func creerClesSiAbsentes() throws {
        if try lireElement(.aes) == nil {
            let nouvelle = SymmetricKey(size: .bits256)
            let octets = nouvelle.withUnsafeBytes { Data($0) }
            try ecrireElement(octets, .aes)
        }

        if try lireElement(.seBloc) == nil {
            guard let controle = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage, .userPresence],
                nil
            ) else {
                throw ErreurListeDeConfiance.erreurSysteme
            }
            let cle: SecureEnclave.P256.Signing.PrivateKey
            do {
                cle = try SecureEnclave.P256.Signing.PrivateKey(accessControl: controle)
            } catch {
                throw ErreurListeDeConfiance.erreurSysteme
            }
            try ecrireElement(cle.dataRepresentation, .seBloc)
            try ecrireElement(cle.publicKey.rawRepresentation, .publique)
        }
    }

    /// Lit la clé AES de la liste. Une clé absente est une erreur de déchiffrement.
    private func lireCleAES() throws -> SymmetricKey {
        guard let octets = try lireElement(.aes) else {
            throw ErreurListeDeConfiance.dechiffrementEchoue
        }
        return SymmetricKey(data: octets)
    }

    /// Lit la clé publique de vérification. Une clé absente rend la liste non vérifiable.
    private func lireClePublique() throws -> P256.Signing.PublicKey {
        guard let octets = try lireElement(.publique) else {
            throw ErreurListeDeConfiance.signatureInvalide
        }
        guard let cle = try? P256.Signing.PublicKey(rawRepresentation: octets) else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
        return cle
    }

    /// Recharge la clé privée de la Secure Enclave depuis son bloc de données.
    /// Le chargement ne demande pas d'authentification : c'est la signature qui la demande.
    private func lireClePriveeSE() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard let bloc = try lireElement(.seBloc) else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: bloc)
        } catch {
            throw ErreurListeDeConfiance.erreurSysteme
        }
    }

    // MARK: - Version

    /// Lit la version mémorisée. Absente, elle vaut 0.
    private func lireVersionMemorisee() throws -> UInt64 {
        guard let octets = try lireElement(.version) else {
            return 0
        }
        guard octets.count == 8 else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
        return octets.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    /// Mémorise la version après une lecture ou une écriture réussie.
    private func ecrireVersionMemorisee(_ version: UInt64) throws {
        let octets = withUnsafeBytes(of: version.bigEndian) { Data($0) }
        try ecrireElement(octets, .version)
    }

    // MARK: - Keychain

    private func ecrireElement(_ donnees: Data, _ compte: Compte) throws {
        let requete = requeteKeychain(compte)
        SecItemDelete(requete as CFDictionary)

        var ajout = requete
        ajout[kSecValueData as String] = donnees
        guard SecItemAdd(ajout as CFDictionary, nil) == errSecSuccess else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
    }

    /// Lit un élément du Keychain. Renvoie `nil` si l'élément n'existe pas.
    private func lireElement(_ compte: Compte) throws -> Data? {
        var requete = requeteKeychain(compte)
        requete[kSecReturnData as String] = true
        requete[kSecMatchLimit as String] = kSecMatchLimitOne

        var resultat: AnyObject?
        let statut = SecItemCopyMatching(requete as CFDictionary, &resultat)
        if statut == errSecItemNotFound {
            return nil
        }
        guard statut == errSecSuccess, let donnees = resultat as? Data else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
        return donnees
    }

    private func supprimerElement(_ compte: Compte) throws {
        let statut = SecItemDelete(requeteKeychain(compte) as CFDictionary)
        guard statut == errSecSuccess || statut == errSecItemNotFound else {
            throw ErreurListeDeConfiance.erreurSysteme
        }
    }

    /// Requête de base : élément générique, accessible seulement déverrouillé, lié à cet appareil.
    private func requeteKeychain(_ compte: Compte) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: compte.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
