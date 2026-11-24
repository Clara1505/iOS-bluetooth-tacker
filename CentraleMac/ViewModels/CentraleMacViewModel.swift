import Foundation
#if canImport(Observation)
import Observation
#endif

/// Vue-Modèle de la centrale Mac (architecture MVVM, `MAC-1` et préparation `MAC-7`).
///
/// Responsabilités :
/// - Piloter le service de réception réseau à travers `ServiceReceptionAlertesProtocol`.
/// - Conserver l'historique des alertes reçues **uniquement en mémoire vive (RAM)**, sans aucune écriture
///   dans un fichier ni dans `UserDefaults` (`ARCH-7`, menace `I4`).
/// - Appliquer un plafond en mémoire sur le nombre d'alertes conservées pendant la séance (contre `D2`).
/// - Fournir la purge immédiate en mémoire pour la fin de séance (`MAC-7`, menace `I4`).
#if canImport(Observation)
@Observable
#endif
public final class CentraleMacViewModel {
    /// Plafond de sécurité du nombre d'alertes gardées en mémoire vive pendant une séance (contre `D2`).
    public static let nombreMaxAlertesEnMemoire = 500

    /// État courant du serveur de réception TCP.
    public private(set) var etatServeur: EtatServeurCentrale = .arrete
    /// Historique des alertes reçues pendant la séance, triées de la plus récente à la plus ancienne (en RAM uniquement).
    public private(set) var alertesRecues: [Alerte] = []
    /// Compteur du nombre de trames invalides ou suspectes rejetées en sécurité pendant la séance.
    public private(set) var nombreTramesRejetees: Int = 0
    /// Dernière erreur de transport relevée (sans aucune donnée personnelle ni identifiant brut, menace `I2`).
    public private(set) var derniereErreurTransport: ErreurTransportCentrale?

    /// Service réseau injecté via son protocole (permet l'injection d'un bouchon dans les tests unitaires).
    private let serviceReception: ServiceReceptionAlertesProtocol

    /// Initialise le Vue-Modèle avec le service de réception souhaité.
    ///
    /// - Parameter serviceReception: Implémentation réelle (`ServiceReceptionAlertes`) ou bouchon de test.
    public init(serviceReception: ServiceReceptionAlertesProtocol) {
        self.serviceReception = serviceReception
        configurerRappelsService()
    }

    /// Démarre l'écoute des alertes entrantes sur le réseau local.
    public func demarrerCentrale() {
        serviceReception.demarrerEcoute()
    }

    /// Arrête l'écoute réseau de la centrale.
    public func arreterCentrale() {
        serviceReception.arreterEcoute()
    }

    /// Purge intégralement l'historique des alertes et les compteurs en mémoire vive (`MAC-1` / `MAC-7`).
    ///
    /// Menace STRIDE visée : `I4` (aucune donnée laissée à l'utilisateur suivant du Mac prêté).
    public func purgerHistoriqueSession() {
        alertesRecues.removeAll()
        nombreTramesRejetees = 0
        derniereErreurTransport = nil
    }

    /// Retourne les alertes filtrées selon un niveau de gravité optionnel (`nil` retourne tout l'historique).
    ///
    /// - Parameter niveau: Niveau à filtrer (`info`, `alerte`, `critique`) ou `nil`.
    /// - Returns: Les alertes correspondantes, de la plus récente à la plus ancienne.
    public func alertesFiltrees(par niveau: NiveauAlerte?) -> [Alerte] {
        guard let niveau = niveau else {
            return alertesRecues
        }
        return alertesRecues.filter { $0.niveau == niveau }
    }

    // MARK: - Liaison interne avec le service réseau

    /// Relie les événements du service réseau à l'état en mémoire du Vue-Modèle.
    private func configurerRappelsService() {
        serviceReception.surChangementEtat = { [weak self] nouvelEtat in
            guard let self = self else { return }
            self.executerSurFilPrincipal {
                self.etatServeur = nouvelEtat
            }
        }

        serviceReception.surReceptionAlerte = { [weak self] nouvelleAlerte in
            guard let self = self else { return }
            self.executerSurFilPrincipal {
                self.enregistrerAlerteEnMemoire(nouvelleAlerte)
            }
        }

        serviceReception.surRejetTrame = { [weak self] erreur in
            guard let self = self else { return }
            self.executerSurFilPrincipal {
                self.nombreTramesRejetees += 1
                self.derniereErreurTransport = erreur
            }
        }
    }

    /// Exécute la mise à jour d'état directement si l'appel est déjà sur le thread principal (ex. tests unitaires),
    /// ou la bascule sur `DispatchQueue.main` si elle provient de la file réseau en arrière-plan.
    private func executerSurFilPrincipal(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    /// Ajoute une alerte validée en tête d'historique en mémoire, en ignorant les doublons d'`id`
    /// et en respectant le plafond `nombreMaxAlertesEnMemoire`.
    private func enregistrerAlerteEnMemoire(_ alerte: Alerte) {
        // Déduplication par identifiant d'événement.
        guard !alertesRecues.contains(where: { $0.id == alerte.id }) else {
            return
        }

        alertesRecues.insert(alerte, at: 0)

        // Application du plafond mémoire (D2) : suppression des plus anciennes au-delà de 500 entrées.
        if alertesRecues.count > Self.nombreMaxAlertesEnMemoire {
            alertesRecues.removeLast(alertesRecues.count - Self.nombreMaxAlertesEnMemoire)
        }
    }
}
