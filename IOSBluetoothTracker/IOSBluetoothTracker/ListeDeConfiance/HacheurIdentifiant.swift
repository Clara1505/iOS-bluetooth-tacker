import Foundation

/// Calcule l'identifiant haché d'un appareil détecté (I5).
/// L'implémentation HMAC-SHA256 avec la clé du Keychain est fournie par TRU-6 (relue par Aida).
protocol HacheurIdentifiant {
    /// - Parameter identifiant: identifiant système de l'appareil, jamais stocké tel quel.
    /// - Returns: l'identifiant haché à enregistrer dans la liste de confiance.
    func hacher(_ identifiant: UUID) -> Data
}