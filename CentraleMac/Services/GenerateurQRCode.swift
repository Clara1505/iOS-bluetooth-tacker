import Foundation
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Générateur d'image de QR code utilisant exclusivement le framework natif Apple `CoreImage` (`MAC-2`).
///
/// Conforme à `CLAUDE.md` (§5 et §7) :
/// - Aucune dépendance tierce.
/// - Aucun déballage forcé (`!`, `try!`, `fatalError`).
/// - Validation de la taille de la charge utile avant génération (`<= 1 024` octets, contre `T4`).
public enum GenerateurQRCode {
    #if canImport(CoreImage) && canImport(CoreGraphics)
    /// Génère un `CGImage` représentant le QR code des données fournies.
    ///
    /// - Parameters:
    ///   - donnees: Les octets JSON de `ChargeUtileQRAppairage` (entre 1 et 1 024 octets).
    ///   - facteurEchelle: Facteur d'agrandissement sans flou (10 par défaut pour un affichage net sur écran Retina).
    /// - Returns: Le `CGImage` du QR code, ou `nil` si les données sont hors bornes ou si CoreImage échoue.
    public static func genererImageQR(depuis donnees: Data, facteurEchelle: CGFloat = 10.0) -> CGImage? {
        guard !donnees.isEmpty,
              donnees.count <= ChargeUtileQRAppairage.tailleMaxOctetsQR,
              facteurEchelle > 0 else {
            return nil
        }

        guard let filtre = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filtre.setValue(donnees, forKey: "inputMessage")
        // Niveau de correction d'erreur "M" (15 %) : bon équilibre entre densité et lisibilité par la caméra iPhone.
        filtre.setValue("M", forKey: "inputCorrectionLevel")

        guard let imageSortie = filtre.outputImage else {
            return nil
        }

        let transformation = CGAffineTransform(scaleX: facteurEchelle, y: facteurEchelle)
        let imageAgrandie = imageSortie.transformed(by: transformation)

        let contexte = CIContext()
        return contexte.createCGImage(imageAgrandie, from: imageAgrandie.extent)
    }
    #endif
}
