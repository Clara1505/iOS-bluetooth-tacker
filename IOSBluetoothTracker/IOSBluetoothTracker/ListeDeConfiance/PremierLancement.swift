import Foundation

/// Réinitialisation au premier lancement après installation (CHOIX_CRYPTO §3.8, menace I5).
/// Les éléments du Keychain peuvent survivre à la désinstallation, pas `UserDefaults` : un drapeau absent
/// signifie donc « première exécution depuis l'installation ».
struct PremierLancement {

    /// Clé du drapeau dans `UserDefaults`.
    static let cleDrapeau = "fr.tracker.bluetooth.deja-lance"

    private let defauts: UserDefaults
    private let actions: [() throws -> Void]

    /// - Parameters:
    ///   - defauts: où se trouve le drapeau.
    ///   - actions: suppressions à faire (liste de confiance, clé HMAC…). À exécuter avant toute création de clé.
    init(defauts: UserDefaults, actions: [() throws -> Void]) {
        self.defauts = defauts
        self.actions = actions
    }

    /// Exécute les actions une seule fois. Le drapeau n'est posé qu'après leur réussite :
    /// en cas d'échec, elles sont retentées au lancement suivant.
    /// - Returns: `true` si les actions ont été exécutées.
    @discardableResult
    func executerSiNecessaire() throws -> Bool {
        guard !defauts.bool(forKey: Self.cleDrapeau) else {
            return false
        }
        for action in actions {
            try action()
        }
        defauts.set(true, forKey: Self.cleDrapeau)
        return true
    }
}