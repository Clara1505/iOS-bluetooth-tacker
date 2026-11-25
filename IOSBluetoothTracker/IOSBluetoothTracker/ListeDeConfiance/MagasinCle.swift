import Foundation
import Security

/// Erreurs du hachage des identifiants (TRU-6).
enum ErreurHachage: Error, Equatable {
    /// La clé enregistrée n'a pas la taille attendue (32 octets).
    case cleInvalide
    /// Erreur du Keychain.
    case erreurSysteme
}

/// Stockage de la clé secrète du HMAC. Protocole pour pouvoir tester sans Keychain.
protocol MagasinCle {
    /// - Returns: les octets de la clé, ou `nil` si elle n'existe pas encore.
    func lire() throws -> Data?
    func ecrire(_ octets: Data) throws
    func supprimer() throws
}

/// Clé du HMAC dans le Keychain, accessible seulement déverrouillé et liée à cet appareil (§3.4).
final class MagasinCleKeychain: MagasinCle {

    private static let service = "fr.tracker.bluetooth.hmac"
    private static let compte = "cle"

    func lire() throws -> Data? {
        var requete = requeteDeBase()
        requete[kSecReturnData as String] = true
        requete[kSecMatchLimit as String] = kSecMatchLimitOne

        var resultat: AnyObject?
        let statut = SecItemCopyMatching(requete as CFDictionary, &resultat)
        if statut == errSecItemNotFound {
            return nil
        }
        guard statut == errSecSuccess, let octets = resultat as? Data else {
            throw ErreurHachage.erreurSysteme
        }
        return octets
    }

    func ecrire(_ octets: Data) throws {
        let requete = requeteDeBase()
        SecItemDelete(requete as CFDictionary)

        var ajout = requete
        ajout[kSecValueData as String] = octets
        guard SecItemAdd(ajout as CFDictionary, nil) == errSecSuccess else {
            throw ErreurHachage.erreurSysteme
        }
    }

    func supprimer() throws {
        let statut = SecItemDelete(requeteDeBase() as CFDictionary)
        guard statut == errSecSuccess || statut == errSecItemNotFound else {
            throw ErreurHachage.erreurSysteme
        }
    }

    private func requeteDeBase() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.compte,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}