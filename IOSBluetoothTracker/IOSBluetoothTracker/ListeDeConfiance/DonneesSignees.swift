import Foundation

/// Construction des données signées et règle de version de la liste de confiance (CHOIX_CRYPTO.md, §3.6).
enum DonneesSignees {
    /// Libellé fixe : empêche de réutiliser une signature produite pour un autre usage.
    static let libelle = Data("liste-confiance-v1".utf8)

    /// Construit les données signées : libellé, puis numéro de version sur 8 octets (big-endian),
    /// puis bloc chiffré complet (nonce, données chiffrées, étiquette AES-GCM).
    /// - Parameters:
    ///   - version: numéro de version de la liste.
    ///   - bloc: bloc chiffré produit par AES-GCM.
    /// - Returns: les octets à signer.
    static func construire(version: UInt64, bloc: Data) -> Data {
        var donnees = libelle
        donnees.append(withUnsafeBytes(of: version.bigEndian) { Data($0) })
        donnees.append(bloc)
        return donnees
    }

    /// Vérifie la version lue par rapport à la version mémorisée dans le Keychain.
    /// - Parameters:
    ///   - lue: version du fichier lu.
    ///   - memorisee: version mémorisée dans le Keychain (0 si absente).
    /// - Returns: `true` si la version lue est plus récente et doit être mémorisée.
    /// - Throws: `ErreurListeDeConfiance.versionPerimee` si la version lue est plus ancienne,
    ///   ce qui empêche de remettre en place une ancienne liste correctement signée.
    static func accepterVersion(lue: UInt64, memorisee: UInt64) throws -> Bool {
        if lue < memorisee {
            throw ErreurListeDeConfiance.versionPerimee
        }
        return lue > memorisee
    }
}
