#if canImport(Network)
import Foundation
import Network

/// Implémentation du serveur de réception de la centrale Mac utilisant `Network.framework` en TCP (`MAC-1`, `MAC-6`).
///
/// Conforme aux décisions d'`ARCH-2` (`docs/architecture/transport.md`), de `MAC-1` et de `MAC-6` :
/// - Écoute TCP locale via `NWListener` et annonce Bonjour `_antitracker._tcp`.
/// - Plafond strict d'**une seule connexion simultanée** (`nombreMaxConnexionsSimultanees = 1`, `C1`/`C2`, contre `D2`).
/// - **Délai d'inactivité (*timeout*) de 10 secondes** coupant toute connexion silencieuse (*slowloris*, `C2`, contre `D2`).
/// - Cadrage des messages par préfixe de longueur sur 4 octets (`CadrageTrameTCP`) avec plafond strict à 64 Ko (`D2`, `D3`).
/// - Interdiction de l'interface cellulaire pour confiner le trafic au réseau local / hotspot (`F3`).
/// - Aucun déballage forcé (`!`, `try!`, `fatalError`) ni journalisation de données personnelles (`I2`).
public final class ServiceReceptionAlertes: ServiceReceptionAlertesProtocol {
    /// Type du service Bonjour annoncé sur le réseau local (hotspot).
    public static let typeServiceBonjour = "_antitracker._tcp"
    /// Nom du service Bonjour annoncé par la centrale Mac.
    public static let nomServiceBonjour = "CentraleAntiTraceur"
    /// Un seul capteur iPhone connecté à la fois : tout second client TCP est immédiatement refusé (`C1`, `C2`, `D2`).
    public static let nombreMaxConnexionsSimultanees = 1
    /// Délai maximal d'attente en secondes pour recevoir une trame complète avant coupure d'une connexion silencieuse (`C2`, `D2`).
    public static let delaiMaxInactiviteSecondes: TimeInterval = 10.0

    public var surChangementEtat: ((EtatServeurCentrale) -> Void)?
    public var surReceptionAlerte: ((Alerte) -> Void)?
    public var surRejetTrame: ((ErreurTransportCentrale) -> Void)?

    /// File série dédiée aux opérations réseau de la centrale.
    private let fileReseau = DispatchQueue(label: "fr.epita.antitracker.centrale.reseau")
    /// Écouteur TCP `Network.framework`.
    private var ecouteur: NWListener?
    /// Connexions clientes actives indexées par un identifiant interne de session réseau.
    private var connexionsActives: [UUID: NWConnection] = [:]
    /// Minuteurs de délai d'inactivité (*timeout*) indexés par identifiant de connexion (`C2`, `MAC-6`).
    private var minuteursInactivite: [UUID: DispatchWorkItem] = [:]
    /// Port TCP actuellement attribué à l'écouteur.
    private var portActuel: UInt16 = 0
    /// Port TCP souhaité (`.any` par défaut pour laisser macOS attribuer un port libre).
    private let portSouhaite: NWEndpoint.Port

    /// Crée un service de réception d'alertes TCP.
    ///
    /// - Parameter port: Port TCP d'écoute (`.any` par défaut).
    public init(port: NWEndpoint.Port = .any) {
        self.portSouhaite = port
    }

    /// Démarre le serveur TCP (`NWListener`) et publie l'annonce Bonjour `_antitracker._tcp`.
    public func demarrerEcoute() {
        fileReseau.async { [weak self] in
            guard let self = self else { return }
            guard self.ecouteur == nil else { return }

            self.notifierEtat(.demarrage)

            let parametres = NWParameters.tcp
            // Confinement au réseau local / hotspot Wi-Fi uniquement.
            parametres.prohibitedInterfaceTypes = [.cellular]
            parametres.acceptLocalOnly = true

            let nouvelEcouteur: NWListener
            do {
                nouvelEcouteur = try NWListener(using: parametres, on: self.portSouhaite)
            } catch {
                self.notifierEtat(.erreur(description: "Impossible d'initialiser l'écouteur TCP local."))
                return
            }

            // Publication du service Bonjour sur le réseau local (hotspot).
            nouvelEcouteur.service = NWListener.Service(
                name: Self.nomServiceBonjour,
                type: Self.typeServiceBonjour
            )

            nouvelEcouteur.stateUpdateHandler = { [weak self] nouvelEtat in
                self?.gererChangementEtatEcouteur(nouvelEtat)
            }

            nouvelEcouteur.newConnectionHandler = { [weak self] nouvelleConnexion in
                self?.gererNouvelleConnexion(nouvelleConnexion)
            }

            self.ecouteur = nouvelEcouteur
            nouvelEcouteur.start(queue: self.fileReseau)
        }
    }

    /// Arrête l'écouteur TCP et ferme proprement toutes les connexions clientes en cours.
    public func arreterEcoute() {
        fileReseau.async { [weak self] in
            guard let self = self else { return }
            self.fermerInterne()
            self.notifierEtat(.arrete)
        }
    }

    // MARK: - Gestion interne du cycle de vie réseau

    /// Libère l'écouteur, annule les minuteurs et ferme toutes les connexions actives (doit être appelé sur `fileReseau`).
    private func fermerInterne() {
        for (_, minuteur) in minuteursInactivite {
            minuteur.cancel()
        }
        minuteursInactivite.removeAll()

        for (_, connexion) in connexionsActives {
            connexion.stateUpdateHandler = nil
            connexion.cancel()
        }
        connexionsActives.removeAll()

        ecouteur?.stateUpdateHandler = nil
        ecouteur?.newConnectionHandler = nil
        ecouteur?.cancel()
        ecouteur = nil
        portActuel = 0
    }

    /// Traite les transitions d'état du `NWListener`.
    private func gererChangementEtatEcouteur(_ etat: NWListener.State) {
        switch etat {
        case .setup, .waiting:
            notifierEtat(.demarrage)
        case .ready:
            let port = ecouteur?.port?.rawValue ?? 0
            portActuel = port
            notifierEtat(.enEcoute(port: port))
        case .failed:
            fermerInterne()
            notifierEtat(.erreur(description: "L'écouteur réseau a échoué et a été fermé en sécurité."))
        case .cancelled:
            fermerInterne()
            notifierEtat(.arrete)
        @unknown default:
            break
        }
    }

    /// Accepte une nouvelle connexion entrante si le plafond `nombreMaxConnexionsSimultanees` (1) n'est pas atteint,
    /// arme le minuteur d'inactivité et lance la lecture du premier en-tête de 4 octets.
    private func gererNouvelleConnexion(_ connexion: NWConnection) {
        // Garde-fou contre un second client ou un flood de connexions TCP simultanées (menace D2, C1, C2).
        guard connexionsActives.count < Self.nombreMaxConnexionsSimultanees else {
            connexion.cancel()
            return
        }

        let idConnexion = UUID()
        connexionsActives[idConnexion] = connexion

        connexion.stateUpdateHandler = { [weak self] etatConnexion in
            guard let self = self else { return }
            switch etatConnexion {
            case .ready:
                self.notifierEtat(.clientConnecte(port: self.portActuel))
                self.lireProchainEntete(sur: connexion, idConnexion: idConnexion)
            case .failed, .cancelled:
                self.retirerConnexion(idConnexion: idConnexion)
            default:
                break
            }
        }

        connexion.start(queue: fileReseau)
    }

    /// Arme ou réarme le délai d'attente maximal (`10 s`) pour une connexion : si le client reste silencieux,
    /// la connexion est coupée et libère la place pour le vrai capteur iPhone (`C2`, `MAC-6`, `D2`).
    private func armerMinuteurInactivite(pour idConnexion: UUID) {
        minuteursInactivite[idConnexion]?.cancel()
        let tacheExpiration = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.connexionsActives[idConnexion] != nil else { return }
            self.notifierRejet(.delaiInactiviteDepasse)
            self.retirerConnexion(idConnexion: idConnexion)
        }
        minuteursInactivite[idConnexion] = tacheExpiration
        fileReseau.asyncAfter(
            deadline: .now() + Self.delaiMaxInactiviteSecondes,
            execute: tacheExpiration
        )
    }

    /// Annule le minuteur d'inactivité d'une connexion.
    private func annulerMinuteurInactivite(pour idConnexion: UUID) {
        minuteursInactivite.removeValue(forKey: idConnexion)?.cancel()
    }

    /// Retire une connexion fermée, annule son minuteur et met à jour l'état du serveur.
    private func retirerConnexion(idConnexion: UUID) {
        annulerMinuteurInactivite(pour: idConnexion)
        guard let connexion = connexionsActives.removeValue(forKey: idConnexion) else {
            return
        }
        connexion.stateUpdateHandler = nil
        connexion.cancel()

        if connexionsActives.isEmpty, ecouteur != nil, portActuel > 0 {
            notifierEtat(.enEcoute(port: portActuel))
        }
    }

    // MARK: - Lecture par préfixe de taille (Length-Prefix Framing, ARCH-2 & MAC-6)

    /// Étape 1 : Lit exactement les 4 octets de l'en-tête de taille (`UInt32` Big-Endian) sous contrôle du minuteur d'inactivité.
    private func lireProchainEntete(sur connexion: NWConnection, idConnexion: UUID) {
        armerMinuteurInactivite(pour: idConnexion)
        let tailleEntete = CadrageTrameTCP.tailleEntete

        connexion.receive(minimumIncompleteLength: tailleEntete, maximumLength: tailleEntete) {
            [weak self] donnees, _, estComplet, erreur in
            guard let self = self else { return }
            self.annulerMinuteurInactivite(pour: idConnexion)

            if erreur != nil {
                self.retirerConnexion(idConnexion: idConnexion)
                return
            }

            guard let entete = donnees, !entete.isEmpty else {
                if estComplet {
                    self.retirerConnexion(idConnexion: idConnexion)
                }
                return
            }

            // Validation immédiate de la taille N (1 <= N <= 64 Ko) avant toute lecture du corps (contre D2 / D3).
            let tailleChargeUtile: Int
            do {
                tailleChargeUtile = try CadrageTrameTCP.validerEnteteTaille(entete)
            } catch let erreurCadrage as ErreurTransportCentrale {
                self.notifierRejet(erreurCadrage)
                self.retirerConnexion(idConnexion: idConnexion)
                return
            } catch {
                self.notifierRejet(.decodageEchoue)
                self.retirerConnexion(idConnexion: idConnexion)
                return
            }

            self.lireChargeUtile(
                tailleAttendue: tailleChargeUtile,
                sur: connexion,
                idConnexion: idConnexion
            )
        }
    }

    /// Étape 2 : Lit exactement les `N` octets de la charge utile validée sous contrôle du minuteur d'inactivité,
    /// décode l'alerte, puis relance la lecture de l'en-tête suivant.
    private func lireChargeUtile(
        tailleAttendue: Int,
        sur connexion: NWConnection,
        idConnexion: UUID
    ) {
        armerMinuteurInactivite(pour: idConnexion)

        connexion.receive(minimumIncompleteLength: tailleAttendue, maximumLength: tailleAttendue) {
            [weak self] donnees, _, estComplet, erreur in
            guard let self = self else { return }
            self.annulerMinuteurInactivite(pour: idConnexion)

            if erreur != nil {
                self.retirerConnexion(idConnexion: idConnexion)
                return
            }

            guard let chargeUtile = donnees, chargeUtile.count == tailleAttendue else {
                let recu = donnees?.count ?? 0
                self.notifierRejet(.trameTronquee(attendu: tailleAttendue, recu: recu))
                self.retirerConnexion(idConnexion: idConnexion)
                return
            }

            do {
                let alerte = try CadrageTrameTCP.decoderAlerte(depuis: chargeUtile)
                self.notifierAlerte(alerte)
            } catch let erreurTransport as ErreurTransportCentrale {
                self.notifierRejet(erreurTransport)
                self.retirerConnexion(idConnexion: idConnexion)
                return
            } catch {
                self.notifierRejet(.decodageEchoue)
                self.retirerConnexion(idConnexion: idConnexion)
                return
            }

            if estComplet {
                self.retirerConnexion(idConnexion: idConnexion)
            } else {
                self.lireProchainEntete(sur: connexion, idConnexion: idConnexion)
            }
        }
    }

    // MARK: - Notifications vers la couche Vue-Modèle

    private func notifierEtat(_ etat: EtatServeurCentrale) {
        surChangementEtat?(etat)
    }

    private func notifierAlerte(_ alerte: Alerte) {
        surReceptionAlerte?(alerte)
    }

    private func notifierRejet(_ erreur: ErreurTransportCentrale) {
        surRejetTrame?(erreur)
    }
}
#endif
