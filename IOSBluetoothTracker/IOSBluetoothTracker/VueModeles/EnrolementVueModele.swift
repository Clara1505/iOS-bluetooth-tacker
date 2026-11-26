import Foundation

/// Vue-modèle de l'enrôlement : nommer un de ses propres appareils pour l'ajouter à la liste de confiance (TRU-1).
///
/// `ObservableObject` et non `@Observable` : la cible minimale est iOS 15 (PM-11).
@MainActor
final class EnrolementVueModele: ObservableObject {

    /// État de l'enrôlement affiché à l'utilisateur.
    enum Etat: Equatable {
        case saisie
        case termine
        case nomInvalide(ErreurNomAppareil)
        case authentificationRefusee
        case erreur
    }

    /// Nom saisi par l'utilisateur, validé seulement à l'ajout.
    @Published var nomSaisi = ""
    @Published private(set) var etat: Etat = .saisie

    private let modificateur: ModificateurListeDeConfiance
    private let hacheur: HacheurIdentifiant
    private let mode: () -> ModeAuthentification
    private let maintenant: () -> Date

    /// - Parameters:
    ///   - modificateur: point d'entrée de modification de la liste (TRU-3).
    ///   - hacheur: calcule l'identifiant haché (TRU-6).
    ///   - mode: méthode d'authentification à enregistrer dans l'historique.
    ///   - maintenant: horloge, remplaçable dans les tests.
    init(
        modificateur: ModificateurListeDeConfiance,
        hacheur: HacheurIdentifiant,
        mode: @escaping () -> ModeAuthentification,
        maintenant: @escaping () -> Date = { Date() }
    ) {
        self.modificateur = modificateur
        self.hacheur = hacheur
        self.mode = mode
        self.maintenant = maintenant
    }

    /// Ajoute l'appareil à la liste de confiance sous le nom saisi.
    /// L'authentification (biométrie ou code du téléphone) est demandée par la Secure Enclave au moment de la signature.
    func enroler(_ appareil: AppareilDetecte) {
        let idHache = hacheur.hacher(appareil.identifiantSysteme)
        do {
            let resultat = try modificateur.ajouterAppareil(
                nomBrut: nomSaisi,
                idHache: idHache,
                date: maintenant(),
                mode: mode()
            )
            switch resultat {
            case .reussie:
                nomSaisi = ""
                etat = .termine
            case .echecAuthentification:
                etat = .authentificationRefusee
            case .erreurSysteme:
                etat = .erreur
            }
        } catch let erreur as ErreurNomAppareil {
            etat = .nomInvalide(erreur)
        } catch {
            etat = .erreur
        }
    }

    /// Revient à l'état de saisie (après une erreur ou un enrôlement terminé).
    func recommencer() {
        etat = .saisie
    }
}

extension ErreurNomAppareil {
    /// Message affiché à l'utilisateur.
    var message: String {
        switch self {
        case .vide:
            return "Donnez un nom à l'appareil."
        case .tropLong:
            return "Le nom ne doit pas dépasser 15 caractères."
        case .caractereNonAutorise:
            return "Utilisez seulement des lettres sans accent, des chiffres et des espaces."
        }
    }
}