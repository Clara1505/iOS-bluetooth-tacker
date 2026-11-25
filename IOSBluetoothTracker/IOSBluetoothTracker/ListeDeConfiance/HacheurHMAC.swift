import CryptoKit
import Foundation

/// Hachage des identifiants : HMAC-SHA256 avec une clé secrète stable (CHOIX_CRYPTO §3.4, menace I5).
/// La clé est créée au premier usage et n'est renouvelée qu'à la réinitialisation des données (§3.8).
final class HacheurHMAC: HacheurIdentifiant {

    /// Taille de la clé : 256 bits.
    static let tailleCleOctets = 32

    private let cle: SymmetricKey

    /// - Parameter magasin: lieu où la clé est conservée.
    /// - Throws: `ErreurHachage.cleInvalide` si une clé de mauvaise taille existe (jamais régénérée en silence,
    ///   car cela changerait tous les identifiants hachés), `ErreurHachage.erreurSysteme` si le Keychain échoue.
    init(magasin: MagasinCle) throws {
        if let octets = try magasin.lire() {
            guard octets.count == Self.tailleCleOctets else {
                throw ErreurHachage.cleInvalide
            }
            cle = SymmetricKey(data: octets)
        } else {
            let nouvelle = SymmetricKey(size: .bits256)
            try magasin.ecrire(nouvelle.withUnsafeBytes { Data($0) })
            cle = nouvelle
        }
    }

    /// - Parameter identifiant: identifiant système de l'appareil observé.
    /// - Returns: le HMAC-SHA256 des 16 octets de l'identifiant (32 octets).
    func hacher(_ identifiant: UUID) -> Data {
        let octets = withUnsafeBytes(of: identifiant.uuid) { Data($0) }
        return Self.calculer(cle: cle, donnees: octets)
    }

    /// Calcul pur, séparé pour être vérifié avec un vecteur de test public.
    static func calculer(cle: SymmetricKey, donnees: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: donnees, using: cle))
    }
}