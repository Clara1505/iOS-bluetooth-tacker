import Foundation
#if canImport(Observation)
import Observation
#endif

/// Vue-Modèle de la centrale Mac (architecture MVVM, `MAC-1`, `MAC-2`, `MAC-3` et préparation `MAC-7`).
///
/// Responsabilités :
/// - Piloter le service de réception réseau à travers `ServiceReceptionAlertesProtocol` (`MAC-1`).
/// - Piloter le service d'appairage par QR code et vérification d'empreinte à travers `ServiceAppairageCryptoProtocol` (`MAC-2`).
/// - Piloter le canal chiffré (ECDH éphémère, HKDF-SHA256 à 1 clé par sens, AES-256-GCM) à travers `ServiceCanalChiffreCryptoProtocol` (`MAC-3`).
/// - Conserver l'historique des alertes reçues et toutes les clés **uniquement en mémoire vive (RAM)**,
///   sans aucune écriture dans un fichier ni dans `UserDefaults` (`ARCH-7`, menace `I4`).
/// - Appliquer un plafond en mémoire sur le nombre d'alertes conservées pendant la séance (contre `D2`).
/// - Fournir la purge immédiate en mémoire (historique + clés de session + clés d'appairage) pour la fin de séance (`MAC-7`, menace `I4`).
#if canImport(Observation)
@Observable
#endif
public final class CentraleMacViewModel {
    /// Plafond de sécurité du nombre d'alertes gardées en mémoire vive pendant une séance (contre `D2`).
    public static let nombreMaxAlertesEnMemoire = 500
    /// Port par défaut utilisé pour l'affichage du QR code si l'écouteur n'a pas encore attribué de port dynamique.
    public static let portParDefautQR: UInt16 = 54321

    /// État courant du serveur de réception TCP.
    public private(set) var etatServeur: EtatServeurCentrale = .arrete
    /// État courant de l'appairage par QR code et de la vérification d'empreinte (`MAC-2`).
    public private(set) var etatAppairage: EtatAppairageMac = .nonAppaire
    /// État courant du canal chiffré ECDH + HKDF + AES-256-GCM (`MAC-3`).
    public private(set) var etatCanalChiffre: EtatCanalChiffreMac = .ferme
    /// Historique des alertes reçues pendant la séance, triées de la plus récente à la plus ancienne (en RAM uniquement).
    public private(set) var alertesRecues: [Alerte] = []
    /// Compteur du nombre de trames invalides ou suspectes rejetées en sécurité pendant la séance.
    public private(set) var nombreTramesRejetees: Int = 0
    /// Dernière erreur de transport relevée (sans aucune donnée personnelle ni identifiant brut, menace `I2`).
    public private(set) var derniereErreurTransport: ErreurTransportCentrale?

    /// Service réseau injecté via son protocole (permet l'injection d'un bouchon dans les tests unitaires).
    private let serviceReception: ServiceReceptionAlertesProtocol
    /// Service cryptographique d'appairage par QR code injecté via son protocole (`MAC-2`).
    private let serviceAppairage: ServiceAppairageCryptoProtocol
    /// Service cryptographique de canal chiffré injecté via son protocole (`MAC-3`).
    private let serviceCanalChiffre: ServiceCanalChiffreCryptoProtocol

    /// Initialise le Vue-Modèle avec les services de réception, d'appairage et de canal chiffré souhaités.
    ///
    /// - Parameters:
    ///   - serviceReception: Implémentation réelle (`ServiceReceptionAlertes`) ou bouchon de test.
    ///   - serviceAppairage: Implémentation crypto (`ServiceAppairageCrypto`) ou bouchon de test.
    ///   - serviceCanalChiffre: Implémentation crypto (`ServiceCanalChiffreCrypto`) ou `nil` (créé automatiquement à partir de `serviceAppairage`).
    public init(
        serviceReception: ServiceReceptionAlertesProtocol,
        serviceAppairage: ServiceAppairageCryptoProtocol = ServiceAppairageCrypto(),
        serviceCanalChiffre: ServiceCanalChiffreCryptoProtocol? = nil
    ) {
        self.serviceReception = serviceReception
        self.serviceAppairage = serviceAppairage
        let canal = serviceCanalChiffre ?? ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)
        self.serviceCanalChiffre = canal
        self.etatAppairage = serviceAppairage.etat
        self.etatCanalChiffre = canal.etat
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

    // MARK: - Actions d'appairage par QR code (MAC-2)

    /// Génère une nouvelle clé d'identité P-256 en RAM et affiche le QR code d'appairage (`MAC-2`).
    /// Toute régénération de QR code ferme également le canal chiffré antérieur en sécurité.
    public func genererQRCodeAppairage() {
        serviceCanalChiffre.purgerCanalEnMemoire()
        etatCanalChiffre = serviceCanalChiffre.etat

        let port = portEcouteActif ?? Self.portParDefautQR
        do {
            _ = try serviceAppairage.demarrerNouvelAppairage(
                nomService: "CentraleAntiTraceur",
                port: port
            )
            etatAppairage = serviceAppairage.etat
        } catch {
            etatAppairage = .rejete(raison: "Impossible de générer le QR code d'appairage.")
        }
    }

    /// Reçoit et vérifie une demande d'appairage d'un iPhone (`MAC-2`, contre `S1`, `S2`).
    ///
    /// - Parameter demande: La demande signée de l'iPhone.
    /// - Returns: La réponse signée du Mac, ou `nil` si la vérification échoue en sécurité.
    @discardableResult
    public func recevoirDemandeAppairage(_ demande: DemandeAppairageIPhone) -> ReponseAppairageMac? {
        do {
            let reponse = try serviceAppairage.traiterDemandeAppairageIPhone(demande)
            etatAppairage = serviceAppairage.etat
            return reponse
        } catch {
            etatAppairage = serviceAppairage.etat
            nombreTramesRejetees += 1
            return nil
        }
    }

    /// Confirme que le code court à 6 chiffres et l'empreinte affichés sur le Mac correspondent à ceux de l'iPhone (`S4`, `E2`).
    public func confirmerAppairage() {
        do {
            try serviceAppairage.confirmerEmpreinteParUtilisateur()
            etatAppairage = serviceAppairage.etat
        } catch {
            etatAppairage = serviceAppairage.etat
        }
    }

    /// Refuse l'appairage si le code court affiché sur le Mac diffère de celui de l'iPhone (`S4`, `E2`).
    public func refuserAppairage() {
        serviceCanalChiffre.purgerCanalEnMemoire()
        etatCanalChiffre = serviceCanalChiffre.etat
        serviceAppairage.refuserEmpreinteParUtilisateur()
        etatAppairage = serviceAppairage.etat
    }

    // MARK: - Actions du canal chiffré ECDH + HKDF + AES-256-GCM (MAC-3)

    /// Établit le canal chiffré à partir du message d'échange ECDH signé de l'iPhone (`MAC-3`, contre `S1`, `I1`, `E2`).
    ///
    /// - Parameter messageECDH: La clé publique ECDH éphémère de l'iPhone et sa signature ECDSA P-256.
    /// - Returns: La réponse ECDH signée du Mac, ou `nil` si l'échange est refusé en sécurité.
    @discardableResult
    public func ouvrirCanalChiffre(_ messageECDH: MessageEchangeECDHIPhone) -> ReponseEchangeECDHMac? {
        do {
            let reponse = try serviceCanalChiffre.etablirCanalDepuisMessageIPhone(messageECDH)
            etatCanalChiffre = serviceCanalChiffre.etat
            return reponse
        } catch {
            etatCanalChiffre = serviceCanalChiffre.etat
            nombreTramesRejetees += 1
            return nil
        }
    }

    /// Déchiffre un événement d'alerte chiffré en `AES-256-GCM` reçu sur le canal sécurisé (`MAC-3`, contre `I1`, `T1`),
    /// valide son format (`ARCH-3`) et l'ajoute à l'historique en mémoire vive.
    ///
    /// - Parameter blocAESGCM: Le bloc combiné AES-GCM (`nonce 12 o || chiffré || tag 16 o`).
    /// - Returns: `true` si l'alerte a été authentifiée, déchiffrée et enregistrée ; `false` en cas de rejet.
    @discardableResult
    public func recevoirAlerteChiffree(_ blocAESGCM: Data) -> Bool {
        do {
            let donneesClaires = try serviceCanalChiffre.dechiffrerMessageDepuisIPhone(blocAESGCM)
            let alerte = try CadrageTrameTCP.decoderAlerte(depuis: donneesClaires)
            enregistrerAlerteEnMemoire(alerte)
            return true
        } catch let erreurTransport as ErreurTransportCentrale {
            nombreTramesRejetees += 1
            derniereErreurTransport = erreurTransport
            return false
        } catch {
            nombreTramesRejetees += 1
            return false
        }
    }

    // MARK: - Purge de fin de séance (MAC-1 / MAC-2 / MAC-3 / MAC-7)

    /// Purge intégralement l'historique des alertes, les clés de session du canal chiffré,
    /// les clés d'appairage et les compteurs en mémoire vive (`MAC-7`).
    ///
    /// Menace STRIDE visée : `I4` (aucune donnée ni clé laissée à l'utilisateur suivant du Mac prêté).
    public func purgerHistoriqueSession() {
        alertesRecues.removeAll()
        nombreTramesRejetees = 0
        derniereErreurTransport = nil
        serviceCanalChiffre.purgerCanalEnMemoire()
        etatCanalChiffre = serviceCanalChiffre.etat
        serviceAppairage.purgerClesEnMemoire()
        etatAppairage = serviceAppairage.etat
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

    /// Port TCP actif de l'écouteur s'il est démarré.
    private var portEcouteActif: UInt16? {
        switch etatServeur {
        case .enEcoute(let port), .clientConnecte(let port):
            return port > 0 ? port : nil
        case .arrete, .demarrage, .erreur:
            return nil
        }
    }

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
