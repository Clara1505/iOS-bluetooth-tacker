import Foundation
#if canImport(Observation)
import Observation
#endif

/// Motif ayant déclenché une purge complète de la centrale Mac (`MAC-7`).
public enum MotifPurgeCentrale: String, Equatable, Sendable {
    /// Purge déclenchée manuellement par l'utilisateur via le bouton de l'interface.
    case actionUtilisateur
    /// Purge déclenchée automatiquement lors de la fermeture de la fenêtre ou de l'application (`C3`).
    case fermetureApplication
}

/// Vue-Modèle de la centrale Mac (architecture MVVM, `MAC-1` à `MAC-7`).
///
/// Responsabilités :
/// - Piloter le service de réception réseau à travers `ServiceReceptionAlertesProtocol` (`MAC-1`).
/// - Piloter le service d'appairage par QR code et vérification d'empreinte à travers `ServiceAppairageCryptoProtocol` (`MAC-2`).
/// - Piloter le canal chiffré (ECDH éphémère, HKDF-SHA256 à 1 clé par sens, AES-256-GCM) à travers `ServiceCanalChiffreCryptoProtocol` (`MAC-3`).
/// - Piloter la vérification de signature ECDSA P-256 (Secure Enclave) et l'anti-rejeu (compteur, nonce, horodatage ±60 s)
///   à travers `ServiceEvenementsSignesCryptoProtocol` (`MAC-4`).
/// - Stocker l'historique des alertes **chiffré en `AES-256-GCM` en mémoire vive** à travers `ServiceHistoriqueChiffreCryptoProtocol` (`MAC-5`),
///   sans aucune écriture dans un fichier ni dans `UserDefaults` (`ARCH-7`, menace `I4`).
/// - Rejeter rapidement en `O(1)` tout message non authentifié ou en excès de débit avant d'invoquer CryptoKit
///   à travers `ServiceLimitationDebitProtocol` (`MAC-6`, menaces `D2`, `E2`).
/// - Fournir la purge immédiate en mémoire (historique chiffré + destruction de clé *crypto-shredding* + état anti-rejeu +
///   clés de session + clés d'appairage + limiteur de débit + arrêt réseau) sur action de l'utilisateur **et** à la fermeture de l'app (`MAC-7`, `I4`, `C3`).
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
    /// Dernier compteur anti-rejeu accepté pour un événement signé (`MAC-4`).
    public private(set) var dernierCompteurAntiRejeu: UInt64 = 0
    /// Nombre d'entrées actuellement chiffrées dans le coffre d'historique en mémoire (`MAC-5`).
    public private(set) var nombreEntreesHistoriqueChiffre: Int = 0
    /// Compteur du nombre de trames invalides ou suspectes rejetées en sécurité pendant la séance.
    public private(set) var nombreTramesRejetees: Int = 0
    /// Dernière décision de rejet rapide ou de limitation de débit (`MAC-6`).
    public private(set) var derniereDecisionFiltrageRapide: DecisionFiltrageRapide?
    /// Dernière erreur de transport relevée (sans aucune donnée personnelle ni identifiant brut, menace `I2`).
    public private(set) var derniereErreurTransport: ErreurTransportCentrale?
    /// Dernière erreur de vérification d'événement signé / anti-rejeu relevée (`MAC-4`).
    public private(set) var derniereErreurEvenementSigne: ErreurEvenementSigneCrypto?
    /// Dernière erreur d'intégrité du coffre d'historique chiffré relevée (`MAC-5`).
    public private(set) var derniereErreurHistoriqueChiffre: ErreurHistoriqueChiffreCrypto?
    /// Nombre total de purges complètes exécutées au cours du cycle de vie de l'application (`MAC-7`).
    public private(set) var nombrePurgesEffectuees: Int = 0
    /// Date de la dernière purge effectuée (`MAC-7`).
    public private(set) var dateDernierePurge: Date?
    /// Motif de la dernière purge effectuée (`actionUtilisateur` ou `fermetureApplication`, `MAC-7` / `C3`).
    public private(set) var dernierMotifPurge: MotifPurgeCentrale?

    /// Alertes déchiffrées à la volée depuis le coffre `AES-256-GCM` en RAM pour l'affichage SwiftUI (`MAC-1` + `MAC-5`).
    ///
    /// En cas d'altération d'une entrée chiffrée (`T3`/`T4`), le coffre échoue en sécurité et retourne une liste vide (`[]`).
    public var alertesRecues: [Alerte] {
        // L'accès à `nombreEntreesHistoriqueChiffre` permet à `@Observable` de rafraîchir automatiquement la vue SwiftUI.
        _ = nombreEntreesHistoriqueChiffre
        do {
            return try serviceHistoriqueChiffre.lireAlertesDechiffrees()
        } catch let erreurCoffre as ErreurHistoriqueChiffreCrypto {
            derniereErreurHistoriqueChiffre = erreurCoffre
            nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
            return []
        } catch {
            return []
        }
    }

    /// Service réseau injecté via son protocole (permet l'injection d'un bouchon dans les tests unitaires).
    private let serviceReception: ServiceReceptionAlertesProtocol
    /// Service cryptographique d'appairage par QR code injecté via son protocole (`MAC-2`).
    private let serviceAppairage: ServiceAppairageCryptoProtocol
    /// Service cryptographique de canal chiffré injecté via son protocole (`MAC-3`).
    private let serviceCanalChiffre: ServiceCanalChiffreCryptoProtocol
    /// Service cryptographique de vérification des événements signés et d'anti-rejeu (`MAC-4`).
    private let serviceEvenementsSignes: ServiceEvenementsSignesCryptoProtocol
    /// Service cryptographique du coffre d'historique chiffré en RAM (`MAC-5`).
    private let serviceHistoriqueChiffre: ServiceHistoriqueChiffreCryptoProtocol
    /// Service de rejet rapide des messages non authentifiés et de limitation de débit (`MAC-6`).
    private let serviceLimitationDebit: ServiceLimitationDebitProtocol

    /// Initialise le Vue-Modèle avec les services de réception, d'appairage, de canal chiffré,
    /// de vérification d'événements signés, de coffre d'historique chiffré et de limitation de débit.
    public init(
        serviceReception: ServiceReceptionAlertesProtocol,
        serviceAppairage: ServiceAppairageCryptoProtocol = ServiceAppairageCrypto(),
        serviceCanalChiffre: ServiceCanalChiffreCryptoProtocol? = nil,
        serviceEvenementsSignes: ServiceEvenementsSignesCryptoProtocol? = nil,
        serviceHistoriqueChiffre: ServiceHistoriqueChiffreCryptoProtocol = ServiceHistoriqueChiffreCrypto(),
        serviceLimitationDebit: ServiceLimitationDebitProtocol = ServiceLimitationDebit()
    ) {
        self.serviceReception = serviceReception
        self.serviceAppairage = serviceAppairage
        let canal = serviceCanalChiffre ?? ServiceCanalChiffreCrypto(serviceAppairage: serviceAppairage)
        self.serviceCanalChiffre = canal
        let verificateurEvenements = serviceEvenementsSignes ?? ServiceEvenementsSignesCrypto(serviceAppairage: serviceAppairage)
        self.serviceEvenementsSignes = verificateurEvenements
        self.serviceHistoriqueChiffre = serviceHistoriqueChiffre
        self.serviceLimitationDebit = serviceLimitationDebit
        self.etatAppairage = serviceAppairage.etat
        self.etatCanalChiffre = canal.etat
        self.dernierCompteurAntiRejeu = verificateurEvenements.dernierCompteurAccepte
        self.nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
        configurerRappelsService()
    }

    deinit {
        // Filet de sécurité supplémentaire (C3, I4) : purge des structures et destruction des clés à la désallocation.
        serviceLimitationDebit.reinitialiserLimiteur()
        serviceHistoriqueChiffre.purgerHistoriqueEtCle(regenererNouvelleCle: false)
        serviceEvenementsSignes.reinitialiserEtatAntiRejeu()
        serviceCanalChiffre.purgerCanalEnMemoire()
        serviceAppairage.purgerClesEnMemoire()
        serviceReception.arreterEcoute()
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
    /// Toute régénération de QR code ferme également le canal chiffré et réinitialise le compteur anti-rejeu et le limiteur.
    public func genererQRCodeAppairage() {
        serviceLimitationDebit.reinitialiserLimiteur()
        derniereDecisionFiltrageRapide = nil
        serviceEvenementsSignes.reinitialiserEtatAntiRejeu()
        dernierCompteurAntiRejeu = serviceEvenementsSignes.dernierCompteurAccepte
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
        serviceLimitationDebit.reinitialiserLimiteur()
        derniereDecisionFiltrageRapide = nil
        serviceEvenementsSignes.reinitialiserEtatAntiRejeu()
        dernierCompteurAntiRejeu = serviceEvenementsSignes.dernierCompteurAccepte
        serviceCanalChiffre.purgerCanalEnMemoire()
        etatCanalChiffre = serviceCanalChiffre.etat
        serviceAppairage.refuserEmpreinteParUtilisateur()
        etatAppairage = serviceAppairage.etat
    }

    // MARK: - Actions du canal chiffré (MAC-3), Événements signés (MAC-4) et Rejet rapide / Limitation de débit (MAC-6)

    /// Établit le canal chiffré à partir du message d'échange ECDH signé de l'iPhone (`MAC-3`, contre `S1`, `I1`, `E2`),
    /// et remet à zéro le compteur anti-rejeu et le limiteur de débit pour cette nouvelle session (`MAC-4`, `MAC-6`).
    ///
    /// - Parameter messageECDH: La clé publique ECDH éphémère de l'iPhone et sa signature ECDSA P-256.
    /// - Returns: La réponse ECDH signée du Mac, ou `nil` si l'échange est refusé en sécurité.
    @discardableResult
    public func ouvrirCanalChiffre(_ messageECDH: MessageEchangeECDHIPhone) -> ReponseEchangeECDHMac? {
        serviceLimitationDebit.reinitialiserLimiteur()
        derniereDecisionFiltrageRapide = nil
        serviceEvenementsSignes.reinitialiserEtatAntiRejeu()
        dernierCompteurAntiRejeu = serviceEvenementsSignes.dernierCompteurAccepte

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

    /// Filtre rapidement en `O(1)` le message entrant (`MAC-6` : état d'appairage, état du canal, taille, débit, seuil d'échecs),
    /// puis déchiffre le bloc `AES-256-GCM` (`MAC-3`), vérifie sa signature `P-256 ECDSA` et ses 3 règles anti-rejeu (`MAC-4`),
    /// et enfin le rechiffre dans le coffre d'historique en RAM (`MAC-5`).
    ///
    /// - Parameters:
    ///   - blocAESGCM: Le bloc AES-GCM combiné contenant l'`EvenementAlerteSigne`.
    ///   - dateReferenceMac: L'heure courante du Mac (`Date()` par défaut).
    /// - Returns: `true` si l'événement est autorisé, authentifié, frais et ajouté à l'historique ; `false` s'il est rejeté.
    @discardableResult
    public func recevoirEvenementSigneEtChiffre(
        _ blocAESGCM: Data,
        dateReferenceMac: Date = Date()
    ) -> Bool {
        // 1. Rejet rapide pré-cryptographique et contrôle de débit en O(1) (MAC-6 : contre D2, E2, D3).
        let decision = serviceLimitationDebit.evaluerMessageEntrant(
            tailleOctets: blocAESGCM.count,
            estPairAppaire: serviceAppairage.estAppaire,
            estCanalOuvert: serviceCanalChiffre.estOuvert,
            dateReception: dateReferenceMac
        )
        guard decision == .autorise else {
            derniereDecisionFiltrageRapide = decision
            derniereErreurTransport = .rejeteParLimiteurDebit(decision)
            nombreTramesRejetees += 1
            return false
        }

        // 2. Déchiffrement AES-256-GCM (MAC-3) + vérification de signature ECDSA P-256 et anti-rejeu (MAC-4).
        do {
            let alerte = try serviceEvenementsSignes.dechiffrerEtVerifierEvenement(
                blocChiffreAESGCM: blocAESGCM,
                via: serviceCanalChiffre,
                dateReferenceMac: dateReferenceMac
            )
            serviceLimitationDebit.signalerSuccesAuthentification()
            derniereDecisionFiltrageRapide = .autorise
            dernierCompteurAntiRejeu = serviceEvenementsSignes.dernierCompteurAccepte
            derniereErreurEvenementSigne = nil
            enregistrerAlerteEnMemoire(alerte)
            return true
        } catch let erreurSigne as ErreurEvenementSigneCrypto {
            serviceLimitationDebit.signalerEchecAuthentification()
            nombreTramesRejetees += 1
            derniereErreurEvenementSigne = erreurSigne
            // Si le seuil d'échecs d'authentification consécutifs est atteint, on verrouille immédiatement le canal (MAC-6).
            if serviceLimitationDebit.echecsAuthentificationConsecutifs >=
                serviceLimitationDebit.seuilEchecsAuthentificationConsecutifs {
                serviceCanalChiffre.purgerCanalEnMemoire()
                etatCanalChiffre = .verrouille(raison: "Canal coupé après trop de messages non authentifiés consécutifs (MAC-6).")
            }
            return false
        } catch {
            serviceLimitationDebit.signalerEchecAuthentification()
            nombreTramesRejetees += 1
            if serviceLimitationDebit.echecsAuthentificationConsecutifs >=
                serviceLimitationDebit.seuilEchecsAuthentificationConsecutifs {
                serviceCanalChiffre.purgerCanalEnMemoire()
                etatCanalChiffre = .verrouille(raison: "Canal coupé après trop de messages non authentifiés consécutifs (MAC-6).")
            }
            return false
        }
    }

    /// Filtre rapidement en `O(1)` le message entrant (`MAC-6`), déchiffre l'alerte chiffrée en `AES-256-GCM` (`MAC-3`),
    /// valide son format (`ARCH-3`) et l'ajoute au coffre d'historique chiffré en mémoire vive (`MAC-5`).
    ///
    /// - Parameters:
    ///   - blocAESGCM: Le bloc combiné AES-GCM (`nonce 12 o || chiffré || tag 16 o`).
    ///   - dateReception: L'heure de réception (`Date()` par défaut).
    /// - Returns: `true` si l'alerte a été authentifiée, déchiffrée et enregistrée ; `false` en cas de rejet.
    @discardableResult
    public func recevoirAlerteChiffree(
        _ blocAESGCM: Data,
        dateReception: Date = Date()
    ) -> Bool {
        let decision = serviceLimitationDebit.evaluerMessageEntrant(
            tailleOctets: blocAESGCM.count,
            estPairAppaire: serviceAppairage.estAppaire,
            estCanalOuvert: serviceCanalChiffre.estOuvert,
            dateReception: dateReception
        )
        guard decision == .autorise else {
            derniereDecisionFiltrageRapide = decision
            derniereErreurTransport = .rejeteParLimiteurDebit(decision)
            nombreTramesRejetees += 1
            return false
        }

        do {
            let donneesClaires = try serviceCanalChiffre.dechiffrerMessageDepuisIPhone(blocAESGCM)
            let alerte = try CadrageTrameTCP.decoderAlerte(depuis: donneesClaires)
            serviceLimitationDebit.signalerSuccesAuthentification()
            derniereDecisionFiltrageRapide = .autorise
            enregistrerAlerteEnMemoire(alerte)
            return true
        } catch let erreurTransport as ErreurTransportCentrale {
            serviceLimitationDebit.signalerEchecAuthentification()
            nombreTramesRejetees += 1
            derniereErreurTransport = erreurTransport
            return false
        } catch {
            serviceLimitationDebit.signalerEchecAuthentification()
            nombreTramesRejetees += 1
            return false
        }
    }

    // MARK: - Purge de fin de séance (MAC-7, menace I4, remarque C3)

    /// Indique si la centrale ne contient plus aucune donnée sensible ni clé de session/appairage en mémoire vive (`MAC-7`).
    public var estSessionTotalementPurgee: Bool {
        serviceHistoriqueChiffre.nombreEntreesChiffrees == 0 &&
        nombreEntreesHistoriqueChiffre == 0 &&
        dernierCompteurAntiRejeu == 0 &&
        serviceEvenementsSignes.dernierCompteurAccepte == 0 &&
        serviceEvenementsSignes.nombreNoncesVus == 0 &&
        !serviceCanalChiffre.estOuvert &&
        etatCanalChiffre == .ferme &&
        !serviceAppairage.estAppaire &&
        serviceAppairage.clePubliqueIPhoneAppaire == nil &&
        serviceAppairage.clePubliqueIdentiteMac == nil &&
        etatAppairage == .nonAppaire &&
        serviceLimitationDebit.echecsAuthentificationConsecutifs == 0
    }

    /// Purge intégralement l'historique chiffré (en détruisant sa clé AES-256 par *crypto-shredding*),
    /// l'état anti-rejeu (compteur et nonces), le limiteur de débit, les clés de session du canal chiffré,
    /// les clés d'appairage et les compteurs en mémoire vive (`MAC-5` + `MAC-6` + `MAC-7`).
    ///
    /// Menace STRIDE visée : `I4` (aucune donnée ni clé laissée à l'utilisateur suivant du Mac prêté).
    ///
    /// - Parameters:
    ///   - motif: Motif de la purge (`.actionUtilisateur` par défaut, ou `.fermetureApplication`).
    ///   - arreterReseau: Si `true`, ferme également l'écouteur TCP et toutes les connexions actives.
    public func purgerHistoriqueSession(
        motif: MotifPurgeCentrale = .actionUtilisateur,
        arreterReseau: Bool = false
    ) {
        // 1. Destruction de la clé AES-256 de l'historique et vidage des blocs chiffrés en RAM (MAC-5 / MAC-7).
        let regenererCleCoffre = (motif == .actionUtilisateur)
        serviceHistoriqueChiffre.purgerHistoriqueEtCle(regenererNouvelleCle: regenererCleCoffre)
        nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
        nombreTramesRejetees = 0
        derniereDecisionFiltrageRapide = nil
        derniereErreurTransport = nil
        derniereErreurEvenementSigne = nil
        derniereErreurHistoriqueChiffre = nil

        // 2. Réinitialisation du limiteur de débit et du compteur d'échecs d'authentification (MAC-6).
        serviceLimitationDebit.reinitialiserLimiteur()

        // 3. Réinitialisation du compteur anti-rejeu et de la table des nonces en RAM (MAC-4).
        serviceEvenementsSignes.reinitialiserEtatAntiRejeu()
        dernierCompteurAntiRejeu = serviceEvenementsSignes.dernierCompteurAccepte

        // 4. Destruction des clés symétriques directionnelles AES-256 en RAM (MAC-3).
        serviceCanalChiffre.purgerCanalEnMemoire()
        etatCanalChiffre = serviceCanalChiffre.etat

        // 5. Destruction de la clé privée d'identité du Mac, de la clé publique de l'iPhone et du QR code en RAM (MAC-2).
        serviceAppairage.purgerClesEnMemoire()
        etatAppairage = serviceAppairage.etat

        // 6. Nettoyage défensif des caches volatiles du processus sur le Mac prêté (I4).
        URLCache.shared.removeAllCachedResponses()
        if let identifiantBundle = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifiantBundle)
        }

        // 7. Arrêt optionnel de l'écouteur TCP (systématique lors de la fermeture de l'app).
        if arreterReseau {
            serviceReception.arreterEcoute()
            etatServeur = .arrete
        }

        // 8. Traçabilité de la purge en mémoire pour confirmation visuelle dans l'interface.
        nombrePurgesEffectuees += 1
        dateDernierePurge = Date()
        dernierMotifPurge = motif
    }

    /// Déclenche la purge complète de fin de séance lors de la fermeture de la fenêtre ou de l'application (`MAC-7`, `C3`).
    ///
    /// Coupe l'écouteur TCP et détruit l'intégralité de l'historique chiffré et des clés en mémoire vive.
    public func purgerLorsDeLaFermeture() {
        purgerHistoriqueSession(motif: .fermetureApplication, arreterReseau: true)
    }

    /// Retourne les alertes filtrées selon un niveau de gravité optionnel (`nil` retourne tout l'historique).
    ///
    /// - Parameter niveau: Niveau à filtrer (`info`, `alerte`, `critique`) ou `nil`.
    /// - Returns: Les alertes correspondantes, de la plus récente à la plus ancienne.
    public func alertesFiltrees(par niveau: NiveauAlerte?) -> [Alerte] {
        let toutes = alertesRecues
        guard let niveau = niveau else {
            return toutes
        }
        return toutes.filter { $0.niveau == niveau }
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

    /// Chiffre et ajoute une alerte validée en tête du coffre d'historique en mémoire (`MAC-5`).
    private func enregistrerAlerteEnMemoire(_ alerte: Alerte) {
        do {
            let ajoutee = try serviceHistoriqueChiffre.ajouterAlerteChiffree(alerte)
            if ajoutee {
                nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
                derniereErreurHistoriqueChiffre = nil
            }
        } catch let erreurCoffre as ErreurHistoriqueChiffreCrypto {
            derniereErreurHistoriqueChiffre = erreurCoffre
            nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
        } catch {
            nombreEntreesHistoriqueChiffre = serviceHistoriqueChiffre.nombreEntreesChiffrees
        }
    }
}
