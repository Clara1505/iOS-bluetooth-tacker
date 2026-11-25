import Foundation

/// État courant du serveur de réception de la centrale Mac.
public enum EtatServeurCentrale: Equatable, Sendable {
    /// Le serveur n'est pas démarré.
    case arrete
    /// Le serveur est en cours d'initialisation.
    case demarrage
    /// Le serveur écoute sur le port TCP indiqué et annonce le service Bonjour.
    case enEcoute(port: UInt16)
    /// Un capteur iPhone est actuellement connecté au serveur TCP.
    case clientConnecte(port: UInt16)
    /// Le serveur a rencontré une erreur et s'est arrêté en sécurité.
    case erreur(description: String)
}

/// Erreurs liées au cadrage des trames TCP (*Length-Prefix Framing*) et au décodage des messages réseau.
///
/// Menaces STRIDE visées (`docs/architecture/transport.md`, ARCH-2) :
/// - `D2` : rejet immédiat des trames surdimensionnées avant toute allocation mémoire de taille `N`.
/// - `D3` : rejet sans plantage des trames vides, tronquées ou au format JSON invalide.
public enum ErreurTransportCentrale: Error, Equatable, Sendable {
    /// L'en-tête de taille ne contient pas exactement 4 octets.
    case enteteTailleIncomplet(Int)
    /// La taille annoncée dans l'en-tête vaut 0 octet.
    case trameVide
    /// La taille annoncée dépasse le plafond de sécurité de 64 Ko (`65_536` octets).
    case trameTropGrande(UInt32)
    /// Le corps du message reçu ne correspond pas à la taille annoncée dans l'en-tête.
    case trameTronquee(attendu: Int, recu: Int)
    /// La charge utile JSON est malformée ou ne correspond pas au schéma attendu.
    case decodageEchoue
    /// L'alerte décodée ne respecte pas les contraintes métier (`ErreurValidationAlerte`).
    case alerteInvalide(ErreurValidationAlerte)
    /// La connexion cliente est restée silencieuse au-delà du délai maximal autorisé (`MAC-6`, `C2`, menace `D2`).
    case delaiInactiviteDepasse
    /// Le message a été rejeté par le filtre rapide ou le limiteur de débit (`MAC-6`, menaces `D2`, `E2`).
    case rejeteParLimiteurDebit(DecisionFiltrageRapide)
}

/// Encodeur et décodeur sans état du cadrage TCP à préfixe de taille sur 4 octets (`UInt32` Big-Endian).
///
/// Conforme à `docs/architecture/transport.md` (§3.2, ARCH-2) :
/// ```
/// +------------------------------------+--------------------------------------------------+
/// | En-tête : Taille N (4 octets)      | Charge utile : Message du protocole (N octets)   |
/// | UInt32 en Big-Endian (réseau)      | JSON de l'alerte (puis bloc CryptoKit en MAC-3/4)|
/// +------------------------------------+--------------------------------------------------+
/// ```
public enum CadrageTrameTCP {
    /// Taille exacte de l'en-tête de longueur (4 octets pour un `UInt32`).
    public static let tailleEntete = 4
    /// Plafond strict de sécurité par message : 64 Ko (`65_536` octets) contre la saturation mémoire (`D2`, `D3`).
    public static let tailleMaxMessage: UInt32 = 65_536

    /// Encode un octet-stream (`Data`) en le préfixant par sa taille sur 4 octets en Big-Endian.
    ///
    /// - Parameter chargeUtile: Les octets du message à encapsuler.
    /// - Returns: La trame complète `[4 octets taille][chargeUtile]`.
    /// - Throws: `ErreurTransportCentrale.trameVide` si `chargeUtile` est vide,
    ///           ou `ErreurTransportCentrale.trameTropGrande` si elle dépasse 64 Ko.
    public static func encapsuler(_ chargeUtile: Data) throws -> Data {
        guard !chargeUtile.isEmpty else {
            throw ErreurTransportCentrale.trameVide
        }
        guard chargeUtile.count <= Int(tailleMaxMessage) else {
            let taille = UInt32(clamping: chargeUtile.count)
            throw ErreurTransportCentrale.trameTropGrande(taille)
        }

        var tailleBigEndian = UInt32(chargeUtile.count).bigEndian
        var trame = Data(bytes: &tailleBigEndian, count: tailleEntete)
        trame.append(chargeUtile)
        return trame
    }

    /// Lit et valide l'en-tête de 4 octets d'une trame TCP entrante.
    ///
    /// Cette fonction est appelée **avant** d'allouer ou de lire la charge utile sur la socket TCP,
    /// afin d'empêcher un attaquant sur le réseau local (`M2`) de provoquer un déni de service mémoire (`D2`).
    ///
    /// - Parameter entete: Les 4 premiers octets reçus sur la connexion TCP.
    /// - Returns: La taille validée `N` (comprise entre `1` et `65_536` octets).
    /// - Throws: `ErreurTransportCentrale` si l'en-tête ne fait pas 4 octets, si `N == 0` ou si `N > 65_536`.
    public static func validerEnteteTaille(_ entete: Data) throws -> Int {
        guard entete.count == tailleEntete else {
            throw ErreurTransportCentrale.enteteTailleIncomplet(entete.count)
        }

        // Lecture sans alignement risqué ni force unwrap : assemblage explicite des 4 octets Big-Endian.
        let octets = [UInt8](entete)
        let taille: UInt32 =
            (UInt32(octets[0]) << 24) |
            (UInt32(octets[1]) << 16) |
            (UInt32(octets[2]) << 8)  |
            UInt32(octets[3])

        guard taille > 0 else {
            throw ErreurTransportCentrale.trameVide
        }
        guard taille <= tailleMaxMessage else {
            throw ErreurTransportCentrale.trameTropGrande(taille)
        }

        return Int(taille)
    }

    /// Décode et valide une `Alerte` à partir d'une charge utile JSON de taille déjà bornée.
    ///
    /// - Parameter donnees: Les `N` octets de la charge utile reçue après l'en-tête.
    /// - Returns: L'`Alerte` validée.
    /// - Throws: `ErreurTransportCentrale` si le JSON est malformé ou si les champs violent les contraintes de sécurité.
    public static func decoderAlerte(depuis donnees: Data) throws -> Alerte {
        guard !donnees.isEmpty else {
            throw ErreurTransportCentrale.trameVide
        }
        guard donnees.count <= Int(tailleMaxMessage) else {
            throw ErreurTransportCentrale.trameTropGrande(UInt32(clamping: donnees.count))
        }

        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601

        let alerte: Alerte
        do {
            alerte = try decodeur.decode(Alerte.self, from: donnees)
        } catch {
            throw ErreurTransportCentrale.decodageEchoue
        }

        do {
            try alerte.validerFormat()
        } catch let erreurValidation as ErreurValidationAlerte {
            throw ErreurTransportCentrale.alerteInvalide(erreurValidation)
        } catch {
            throw ErreurTransportCentrale.decodageEchoue
        }

        return alerte
    }
}

/// Contrat abstrait du service de réception d'alertes côté Mac.
///
/// Conformément à `CLAUDE.md` (§7), chaque service est placé derrière un `protocol` afin de permettre
/// son remplacement par un bouchon (*mock*) dans les tests unitaires Swift Testing.
public protocol ServiceReceptionAlertesProtocol: AnyObject {
    /// Appelé à chaque changement d'état du serveur TCP.
    var surChangementEtat: ((EtatServeurCentrale) -> Void)? { get set }
    /// Appelé à chaque fois qu'une alerte valide est reçue depuis l'iPhone.
    var surReceptionAlerte: ((Alerte) -> Void)? { get set }
    /// Appelé lorsqu'une trame invalide ou suspecte est rejetée en sécurité.
    var surRejetTrame: ((ErreurTransportCentrale) -> Void)? { get set }

    /// Démarre l'écoute réseau des alertes entrantes.
    func demarrerEcoute()
    /// Arrête l'écoute et ferme toutes les connexions actives.
    func arreterEcoute()
}
