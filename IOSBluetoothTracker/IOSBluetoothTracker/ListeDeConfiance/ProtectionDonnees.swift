import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Décide si le contenu doit être masqué selon la phase de la scène (TRU-4, menace I3).
enum PolitiqueMasquage {

    /// - Parameter phase: phase courante de la scène SwiftUI.
    /// - Returns: `true` si le contenu doit être masqué (app inactive ou en arrière-plan).
    static func doitMasquer(_ phase: ScenePhase) -> Bool {
        phase != .active
    }
}

/// Remplace le contenu par un écran neutre quand l'app quitte le premier plan.
/// Évite que l'aperçu du sélecteur d'apps montre la liste ou les résultats.
struct ModifierMasquageApercu: ViewModifier {

    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .overlay {
                if PolitiqueMasquage.doitMasquer(phase) {
                    Rectangle()
                        .fill(Color(.systemBackground))
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {

    /// Masque le contenu de la vue dans l'aperçu multitâche.
    /// À appliquer une seule fois, sur la vue racine de l'app.
    func masquerApercuMultitache() -> some View {
        modifier(ModifierMasquageApercu())
    }
}

/// Copie dans le presse-papiers sans synchronisation entre appareils et avec expiration (TRU-4, menace I3).
enum PressePapiersLocal {

    /// Durée de validité par défaut d'une copie, en secondes.
    static let dureeParDefaut: TimeInterval = 60

    /// - Parameters:
    ///   - texte: texte à copier.
    ///   - duree: durée au bout de laquelle le contenu n'est plus disponible.
    static func copier(_ texte: String, duree: TimeInterval = dureeParDefaut) {
        let options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(duree)
        ]
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: texte]],
            options: options
        )
    }
}

/// Vérifie l'attribut de protection d'un fichier (TRU-4, menace I6).
enum VerificationProtection {

    /// - Parameter url: fichier à contrôler.
    /// - Returns: `true` si le fichier a la protection « Complete ».
    /// - Throws: l'erreur système si les attributs du fichier ne peuvent pas être lus.
    static func estProtegeComplete(_ url: URL) throws -> Bool {
        let attributs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributs[.protectionKey] as? FileProtectionType == .complete
    }
}