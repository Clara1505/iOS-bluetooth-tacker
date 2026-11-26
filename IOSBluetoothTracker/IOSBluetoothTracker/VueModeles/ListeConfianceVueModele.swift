import Foundation

/// Vue-modèle de l'écran de la liste de confiance .
///
/// `ObservableObject` et non `@Observable` : la cible minimale est iOS 15 (PM-11).
@MainActor
final class ListeConfianceVueModele: ObservableObject {

    /// Contenu de la dernière lecture réussie de la liste.
    @Published private(set) var contenu = ContenuListe()
    /// `true` si la liste n'a pas pu être lue ou vérifiée : l'écran ne doit pas afficher « liste vide ».
    @Published private(set) var listeIllisible = false
    /// Message d'erreur de la dernière suppression, ou `nil`.
    @Published private(set) var messageErreur: String?

    private let stockage: StockageListeDeConfiance
    private let modificateur: ModificateurListeDeConfiance
    private let mode: () -> ModeAuthentification
    private let maintenant: () -> Date

    /// - Parameters:
    ///   - stockage: lecture de la liste (sans authentification).
    ///   - modificateur: suppression d'un appareil (avec authentification, TRU-3).
    ///   - mode: méthode d'authentification à enregistrer dans l'historique.
    ///   - maintenant: horloge, remplaçable dans les tests.
    init(
        stockage: StockageListeDeConfiance,
        modificateur: ModificateurListeDeConfiance,
        mode: @escaping () -> ModeAuthentification,
        maintenant: @escaping () -> Date = { Date() }
    ) {
        self.stockage = stockage
        self.modificateur = modificateur
        self.mode = mode
        self.maintenant = maintenant
    }

    /// Relit la liste. En cas d'échec, la liste est marquée illisible et le contenu est vidé.
    func charger() {
        do {
            contenu = try stockage.lire()
            listeIllisible = false
        } catch {
            contenu = ContenuListe()
            listeIllisible = true
        }
    }

    /// Retire un appareil de la liste après authentification, puis relit la liste.
    func supprimer(_ appareil: AppareilDeConfiance) {
        let resultat = modificateur.supprimerAppareil(
            nomAppareil: appareil.nom,
            idHache: appareil.idHache,
            date: maintenant(),
            mode: mode()
        )
        messageErreur = resultat.messageUtilisateur
        charger()
    }
}

extension ResultatModificationListe {
    /// Message affiché à l'utilisateur, `nil` en cas de réussite.
    var messageUtilisateur: String? {
        switch self {
        case .reussie:
            return nil
        case .echecAuthentification:
            return "Authentification refusée : la liste n'a pas été modifiée."
        case .erreurSysteme:
            return "Une erreur est survenue : la liste n'a pas été modifiée."
        }
    }
}