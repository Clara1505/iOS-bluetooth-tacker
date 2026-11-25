import Foundation

/// Résultat d'une tentative de modification de la liste de confiance (TRU-3).
enum ResultatModificationListe: Equatable {
    /// La liste a été modifiée, signée et enregistrée.
    case reussie
    /// L'utilisateur n'a pas été authentifié (Face ID échoué ou code incorrect). Rien n'a été écrit.
    case echecAuthentification
    /// Erreur technique ou d'intégrité. Rien n'a été écrit.
    case erreurSysteme
}

/// Traduit une erreur de la couche stockage en résultat affichable à l'utilisateur.
enum InterpretationErreurModification {

    /// - Parameter erreur: erreur remontée par `StockageListeDeConfiance.modifier`.
    /// - Returns: le résultat à afficher. Une erreur inconnue devient `erreurSysteme`.
    static func resultat(pour erreur: Error) -> ResultatModificationListe {
        guard let erreurListe = erreur as? ErreurListeDeConfiance else {
            return .erreurSysteme
        }
        switch erreurListe {
        case .authentificationEchouee:
            return .echecAuthentification
        default:
            return .erreurSysteme
        }
    }
}

/// Point d'entrée unique pour modifier la liste (TRU-3).
/// Toute modification passe par la signature de la Secure Enclave : sans authentification réussie, rien n'est écrit.
final class ModificateurListeDeConfiance {

    private let stockage: StockageListeDeConfiance

    /// - Parameter stockage: accès à la liste (protocole, pour pouvoir tester avec un faux stockage).
    init(stockage: StockageListeDeConfiance) {
        self.stockage = stockage
    }

    /// Ajoute un appareil à la liste de confiance après authentification.
    /// - Parameters:
    ///   - nomBrut: nom saisi par l'utilisateur, validé par `NomAppareil`.
    ///   - idHache: identifiant haché de l'appareil.
    ///   - date: date de l'action, reprise dans l'historique.
    ///   - mode: méthode d'authentification enregistrée dans l'historique.
    /// - Throws: `ErreurNomAppareil` si le nom n'est pas valide. Dans ce cas, le stockage n'est pas appelé.
    /// - Returns: `reussie`, `echecAuthentification` ou `erreurSysteme`.
    func ajouterAppareil(
        nomBrut: String,
        idHache: Data,
        date: Date,
        mode: ModeAuthentification
    ) throws -> ResultatModificationListe {
        let nom = try NomAppareil(nomBrut)
        let appareil = AppareilDeConfiance(idHache: idHache, nom: nom.valeur, ajouteLe: date)
        let entree = EntreeHistorique(date: date, action: .ajout, nomAppareil: nom.valeur, mode: mode)

        return appliquer(entree: entree) { contenu in
            contenu.appareils.append(appareil)
        }
    }

    /// Supprime un appareil de la liste de confiance après authentification.
    /// - Parameters:
    ///   - nomAppareil: nom de l'appareil, repris dans l'historique.
    ///   - idHache: identifiant haché de l'appareil à retirer.
    ///   - date: date de l'action.
    ///   - mode: méthode d'authentification enregistrée dans l'historique.
    /// - Returns: `reussie`, `echecAuthentification` ou `erreurSysteme`.
    func supprimerAppareil(
        nomAppareil: String,
        idHache: Data,
        date: Date,
        mode: ModeAuthentification
    ) -> ResultatModificationListe {
        let entree = EntreeHistorique(date: date, action: .suppression, nomAppareil: nomAppareil, mode: mode)

        return appliquer(entree: entree) { contenu in
            contenu.appareils.removeAll { $0.idHache == idHache }
        }
    }

    // MARK: - Privé

    /// Applique la modification via le stockage et convertit le résultat.
    private func appliquer(
        entree: EntreeHistorique,
        _ transformation: (inout ContenuListe) -> Void
    ) -> ResultatModificationListe {
        do {
            try stockage.modifier(entree: entree, transformation)
            return .reussie
        } catch {
            return InterpretationErreurModification.resultat(pour: error)
        }
    }
}