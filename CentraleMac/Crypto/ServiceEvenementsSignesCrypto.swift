#if canImport(CryptoKit)
import Foundation
import CryptoKit

// MARK: - Modèles et erreurs des événements signés et de l'anti-rejeu (MAC-4, étiquette `crypto` -> relecture Aïda)

/// Erreurs de vérification cryptographique et d'anti-rejeu pour les événements reçus par la centrale Mac (`MAC-4`).
///
/// Menaces STRIDE couvertes (`docs/securite/STRIDE.md` et `docs/securite/CHOIX_CRYPTO.md` §3.1 et §3.3) :
/// - `S2` : Usurpation de l'iPhone sur le réseau local (`pairNonAppaire`, `signatureECDSAInvalide`).
/// - `R1` : Répudiation de l'origine d'une alerte (`signatureECDSAInvalide`, clé Secure Enclave non exportable).
/// - `T1` : Altération d'un champ de l'alerte ou de ses métadonnées (`signatureECDSAInvalide`, `alerteInvalide`).
/// - `T2` : Rejeu d'un ancien événement ou réordonnancement (`compteurNonStrictementCroissant`, `nonceDejaUtilise`, `horodatageHorsTolerance`).
/// - `D3` : Message malformé (`formatJSONInvalide`, `tailleNonceInvalide`).
public enum ErreurEvenementSigneCrypto: Error, Equatable, Sendable {
    /// Aucun iPhone n'est appairé et confirmé dans `ServiceAppairageCrypto` (`MAC-2`, menaces `S2`, `E2`).
    case pairNonAppaire
    /// La puce matérielle Secure Enclave n'est pas disponible sur cet appareil pour générer une clé matérielle.
    case secureEnclaveIndisponible
    /// La génération de la signature ECDSA P-256 a échoué.
    case echecSignatureMaterielle
    /// Le JSON de l'événement signé est malformé ou dépasse la taille maximale autorisée (`D3`).
    case formatJSONInvalide
    /// L'`Alerte` embarquée ne respecte pas les contraintes de `validerFormat()` (`idHache` != 32 o, `balayagesRefs` vide).
    case alerteInvalide(ErreurValidationAlerte)
    /// Le nonce de l'événement ne mesure pas exactement 16 octets (`T2`, `D3`).
    case tailleNonceInvalide(Int)
    /// La signature ECDSA P-256 est absente, malformée ou ne correspond pas à la clé publique appairée de l'iPhone (`S2`, `R1`, `T1`).
    case signatureECDSAInvalide
    /// Le compteur de l'événement est inférieur ou égal au dernier compteur accepté dans la session (`T2` : rejeu ou retour arrière).
    case compteurNonStrictementCroissant(recu: UInt64, dernierAccepte: UInt64)
    /// Le nonce de 16 octets a déjà été utilisé par un autre événement au cours de la session (`T2`).
    case nonceDejaUtilise
    /// L'écart entre l'horodatage de l'événement et l'horloge du Mac dépasse la tolérance de ±60 secondes (`T2`).
    case horodatageHorsTolerance(ecartSecondes: Int)
}

/// Enveloppe authentifiée et anti-rejeu d'une `Alerte` signée par la Secure Enclave de l'iPhone (`MAC-4`).
///
/// Conforme à `docs/securite/CHOIX_CRYPTO.md` (§3.1 et §3.3) :
/// - `alerte` : l'événement de détection (`id`, `niveau`, `idHache` de 32 octets, `balayagesRefs`, `date`).
/// - `compteur` : entier strictement croissant par session (`1, 2, 3...`), mécanisme principal anti-rejeu (`T2`).
/// - `nonce` : 16 octets aléatoires cryptographiques identifiant de manière unique ce message (`T2`).
/// - `horodatage` : date d'émission vérifiée à ±60 s par la centrale Mac (`T2`).
/// - `signatureECDSA` : signature P-256 (`rawRepresentation`, 64 octets) produite par la clé privée d'identité
///   de l'iPhone sur le bloc canonique couvrant tous les champs ci-dessus (`S2`, `R1`, `T1`).
public struct EvenementAlerteSigne: Codable, Equatable, Sendable {
    /// Taille exacte du nonce anti-rejeu d'un événement (16 octets / 128 bits).
    public static let tailleNonceOctets = 16

    /// L'alerte de sécurité émise par l'iPhone.
    public let alerte: Alerte
    /// Compteur strictement croissant par session (`>= 1`).
    public let compteur: UInt64
    /// Nonce aléatoire unique de 16 octets.
    public let nonce: Data
    /// Horodatage d'émission de l'événement signé (comparé à l'horloge du Mac avec une tolérance de ±60 s).
    public let horodatage: Date
    /// Signature ECDSA P-256 (`rawRepresentation`, 64 octets) couvrant l'intégralité de l'événement.
    public let signatureECDSA: Data

    public init(
        alerte: Alerte,
        compteur: UInt64,
        nonce: Data,
        horodatage: Date,
        signatureECDSA: Data
    ) {
        self.alerte = alerte
        self.compteur = compteur
        self.nonce = nonce
        self.horodatage = horodatage
        self.signatureECDSA = signatureECDSA
    }
}

// MARK: - Protocole d'abstraction de la signature matérielle Secure Enclave (côté iPhone / Tests)

/// Contrat abstrait d'un signataire P-256 ECDSA (`CLAUDE.md` §7 : chaque service est derrière un `protocol`).
///
/// Permet d'utiliser :
/// - `SignataireSecureEnclaveP256` (`SecureEnclave.P256.Signing.PrivateKey`, clé non exportable matériellement, actif `A3`) sur un iPhone réel.
/// - `SignataireMemoireP256` (`P256.Signing.PrivateKey`) dans les tests unitaires sur un Mac dépourvu de Secure Enclave accessible.
public protocol SignataireEvenementP256Protocol {
    /// Clé publique P-256 (`P256.Signing.PublicKey`) correspondant à la clé privée de signature.
    var clePublique: P256.Signing.PublicKey { get }

    /// Signe un bloc d'octets en `P-256 ECDSA` et retourne la signature produite.
    ///
    /// - Parameter donnees: Les octets canoniques de l'événement à signer.
    /// - Returns: La signature `P256.Signing.ECDSASignature`.
    /// - Throws: `ErreurEvenementSigneCrypto` si l'opération de signature échoue.
    func signer(_ donnees: Data) throws -> P256.Signing.ECDSASignature
}

/// Implémentation matérielle utilisant la **Secure Enclave** (`SecureEnclave.P256.Signing.PrivateKey`, actif `A3`).
///
/// Conforme à `docs/securite/CHOIX_CRYPTO.md` (§3.1) :
/// la clé privée est générée à l'intérieur de la puce Secure Enclave et ne peut jamais être exportée.
public final class SignataireSecureEnclaveP256: SignataireEvenementP256Protocol {
    private let clePriveeMaterielle: SecureEnclave.P256.Signing.PrivateKey

    public var clePublique: P256.Signing.PublicKey {
        clePriveeMaterielle.publicKey
    }

    /// Crée une nouvelle clé de signature P-256 non exportable dans la Secure Enclave.
    ///
    /// - Throws: `ErreurEvenementSigneCrypto.secureEnclaveIndisponible` si la puce n'est pas disponible.
    public init() throws {
        guard SecureEnclave.isAvailable else {
            throw ErreurEvenementSigneCrypto.secureEnclaveIndisponible
        }
        do {
            self.clePriveeMaterielle = try SecureEnclave.P256.Signing.PrivateKey()
        } catch {
            throw ErreurEvenementSigneCrypto.secureEnclaveIndisponible
        }
    }

    /// Reconstruit la référence vers une clé Secure Enclave existante à partir de son jeton opaque (`dataRepresentation`).
    ///
    /// Note : `dataRepresentation` d'une clé Secure Enclave n'est pas la clé privée en clair, mais un descripteur
    /// chiffré qui n'est utilisable que par la puce Secure Enclave de ce même appareil (`H3`).
    public init(representationOpaque: Data) throws {
        guard SecureEnclave.isAvailable else {
            throw ErreurEvenementSigneCrypto.secureEnclaveIndisponible
        }
        do {
            self.clePriveeMaterielle = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: representationOpaque
            )
        } catch {
            throw ErreurEvenementSigneCrypto.secureEnclaveIndisponible
        }
    }

    /// Jeton opaque permettant de référencer la clé dans la Secure Enclave de l'appareil.
    public var representationOpaque: Data {
        clePriveeMaterielle.dataRepresentation
    }

    public func signer(_ donnees: Data) throws -> P256.Signing.ECDSASignature {
        do {
            return try clePriveeMaterielle.signature(for: donnees)
        } catch {
            throw ErreurEvenementSigneCrypto.echecSignatureMaterielle
        }
    }
}

/// Implémentation logicielle P-256 en mémoire vive (RAM), produisant des signatures ECDSA P-256
/// au format identique à la Secure Enclave pour les tests unitaires et les environnements sans puce matérielle.
public final class SignataireMemoireP256: SignataireEvenementP256Protocol {
    private let clePrivee: P256.Signing.PrivateKey

    public var clePublique: P256.Signing.PublicKey {
        clePrivee.publicKey
    }

    public init(clePrivee: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) {
        self.clePrivee = clePrivee
    }

    public func signer(_ donnees: Data) throws -> P256.Signing.ECDSASignature {
        do {
            return try clePrivee.signature(for: donnees)
        } catch {
            throw ErreurEvenementSigneCrypto.echecSignatureMaterielle
        }
    }
}

// MARK: - Protocole du service de vérification des événements signés côté Mac (`CLAUDE.md` §7)

/// Contrat abstrait du service de vérification des événements signés et d'anti-rejeu côté Mac (`MAC-4`).
public protocol ServiceEvenementsSignesCryptoProtocol: AnyObject {
    /// Dernier numéro de compteur accepté dans la session courante (`0` au démarrage ou après purge).
    var dernierCompteurAccepte: UInt64 { get }
    /// Nombre de nonces uniques enregistrés dans la session courante.
    var nombreNoncesVus: Int { get }

    /// Vérifie la signature ECDSA P-256 d'un `EvenementAlerteSigne` avec la clé publique appairée de l'iPhone (`S2`, `R1`, `T1`),
    /// contrôle la stricte croissance du compteur, l'unicité du nonce et l'horodatage à ±60 s (`T2`),
    /// puis met à jour l'état anti-rejeu et retourne l'`Alerte` authentifiée.
    ///
    /// - Parameters:
    ///   - evenement: L'événement signé reçu (après déchiffrement AES-256-GCM en `MAC-3`).
    ///   - dateReferenceMac: L'heure courante de l'horloge du Mac (`Date()` par défaut ; injectable pour les tests unitaires).
    /// - Returns: L'`Alerte` validée, authentifiée et fraîche.
    /// - Throws: `ErreurEvenementSigneCrypto` si la signature ou l'une des trois règles anti-rejeu échoue.
    func verifierEtAccepterEvenement(
        _ evenement: EvenementAlerteSigne,
        dateReferenceMac: Date
    ) throws -> Alerte

    /// Déchiffre un bloc `AES-256-GCM` via le canal chiffré (`MAC-3`), désérialise l'`EvenementAlerteSigne`,
    /// vérifie sa signature et ses garde-fous anti-rejeu (`MAC-4`), et retourne l'`Alerte`.
    ///
    /// - Parameters:
    ///   - blocChiffreAESGCM: Le bloc AES-GCM reçu sur la connexion TCP.
    ///   - canalChiffre: Le service de canal chiffré ouvert (`MAC-3`).
    ///   - dateReferenceMac: L'heure courante du Mac (`Date()` par défaut).
    /// - Returns: L'`Alerte` déchiffrée, vérifiée et fraîche.
    /// - Throws: `ErreurCanalChiffreCrypto` ou `ErreurEvenementSigneCrypto`.
    func dechiffrerEtVerifierEvenement(
        blocChiffreAESGCM: Data,
        via canalChiffre: ServiceCanalChiffreCryptoProtocol,
        dateReferenceMac: Date
    ) throws -> Alerte

    /// Réinitialise le compteur anti-rejeu à `0` et vide la table des nonces vus en mémoire vive (`MAC-7`, `I4`).
    func reinitialiserEtatAntiRejeu()
}

// MARK: - Implémentation CryptoKit des événements signés et de l'anti-rejeu (MAC-4)

/// Implémentation cryptographique de la signature des événements et de la vérification anti-rejeu côté Mac (`MAC-4`).
///
/// Conforme à `CLAUDE.md` (§6 et §7) et `docs/securite/CHOIX_CRYPTO.md` (§3.1 et §3.3) :
/// - **Signature ECDSA P-256** vérifiée avec la clé publique de l'iPhone appairé en `MAC-2` (`S2`, `R1`, `T1`).
/// - **Anti-rejeu triple (`T2`)** :
///   1. **Compteur strictement croissant** (`compteur > dernierCompteurAccepte`) : mécanisme principal.
///   2. **Nonce unique de 16 octets** mémorisé dans un ensemble borné en RAM pour la session.
///   3. **Horodatage** vérifié avec une tolérance de **±60 secondes** par rapport à l'horloge du Mac.
/// - **Ordre des vérifications** : l'état anti-rejeu (`dernierCompteurAccepte` et `noncesVus`) n'est modifié
///   **qu'après** la réussite de la vérification de la signature ECDSA et de toutes les vérifications de fraîcheur,
///   afin qu'un attaquant non authentifié ne puisse pas faire avancer le compteur de la centrale (`D2`, `S2`).
public final class ServiceEvenementsSignesCrypto: ServiceEvenementsSignesCryptoProtocol {
    /// Libellé de séparation de domaine inclus en tête des octets signés pour chaque événement d'alerte.
    public static let contexteSignatureEvenement = "antitracker-evenement-alerte-v1"
    /// Tolérance maximale d'écart d'horloge entre l'iPhone et le Mac prêté : 60 secondes (`CHOIX_CRYPTO.md` §3.3).
    public static let toleranceHorodatageSecondes: TimeInterval = 60.0
    /// Plafond de sécurité sur le nombre de nonces gardés en RAM par session (rotation FIFO au-delà pour contrer `D2`).
    public static let nombreMaxNoncesEnMemoire = 2_048

    /// Dernier compteur strictement accepté au cours de la session (`0` tant qu'aucun événement valide n'a été reçu).
    public private(set) var dernierCompteurAccepte: UInt64 = 0

    /// Référence au service d'appairage (`MAC-2`) détenant la clé publique P-256 vérifiée de l'iPhone.
    private let serviceAppairage: ServiceAppairageCryptoProtocol
    /// Ensemble des nonces de 16 octets déjà acceptés au cours de la session courante.
    private var noncesAcceptes: Set<Data> = []
    /// File d'ordre d'arrivée des nonces pour évincer les plus anciens si `nombreMaxNoncesEnMemoire` est atteint.
    private var ordreNoncesAcceptes: [Data] = []

    public var nombreNoncesVus: Int {
        noncesAcceptes.count
    }

    /// Initialise le service de vérification des événements signés en le liant au service d'appairage `MAC-2`.
    ///
    /// - Parameter serviceAppairage: Le service d'appairage fournissant la clé publique appairée de l'iPhone.
    public init(serviceAppairage: ServiceAppairageCryptoProtocol) {
        self.serviceAppairage = serviceAppairage
    }

    // MARK: - Vérification côté Mac (S2, R1, T1, T2)

    public func verifierEtAccepterEvenement(
        _ evenement: EvenementAlerteSigne,
        dateReferenceMac: Date = Date()
    ) throws -> Alerte {
        // 1. Vérifier qu'un iPhone est bien appairé et confirmé par l'utilisateur (contre S2, E2).
        guard serviceAppairage.estAppaire,
              let clePubliqueIPhone = serviceAppairage.clePubliqueIPhoneAppaire else {
            throw ErreurEvenementSigneCrypto.pairNonAppaire
        }

        // 2. Valider le format métier de l'Alerte (`idHache` de 32 octets, `balayagesRefs` non vide, contre D3 / I5).
        do {
            try evenement.alerte.validerFormat()
        } catch let erreurValidation as ErreurValidationAlerte {
            throw ErreurEvenementSigneCrypto.alerteInvalide(erreurValidation)
        } catch {
            throw ErreurEvenementSigneCrypto.formatJSONInvalide
        }

        // 3. Valider la taille exacte du nonce (16 octets).
        guard evenement.nonce.count == EvenementAlerteSigne.tailleNonceOctets else {
            throw ErreurEvenementSigneCrypto.tailleNonceInvalide(evenement.nonce.count)
        }

        // 4. Vérifier la signature ECDSA P-256 AVANT de modifier ou d'accepter le compteur (contre S2, R1, T1, D2).
        //    Un attaquant qui enverrait un compteur = UInt64.max sans signature valide est rejeté sans affecter le compteur !
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: evenement.signatureECDSA)
        } catch {
            throw ErreurEvenementSigneCrypto.signatureECDSAInvalide
        }

        let donneesCanoniquesSignees = Self.construireDonneesCanoniquesASigner(
            alerte: evenement.alerte,
            compteur: evenement.compteur,
            nonce: evenement.nonce,
            horodatage: evenement.horodatage
        )

        guard clePubliqueIPhone.isValidSignature(signature, for: donneesCanoniquesSignees) else {
            throw ErreurEvenementSigneCrypto.signatureECDSAInvalide
        }

        // 5. Anti-rejeu n°1 (Mécanisme principal, T2) : le compteur doit être strictement supérieur au dernier accepté.
        guard evenement.compteur > dernierCompteurAccepte else {
            throw ErreurEvenementSigneCrypto.compteurNonStrictementCroissant(
                recu: evenement.compteur,
                dernierAccepte: dernierCompteurAccepte
            )
        }

        // 6. Anti-rejeu n°2 (T2) : le nonce de 16 octets ne doit jamais avoir été utilisé dans la session.
        guard !noncesAcceptes.contains(evenement.nonce) else {
            throw ErreurEvenementSigneCrypto.nonceDejaUtilise
        }

        // 7. Anti-rejeu n°3 (T2) : l'horodatage doit se trouver dans la fenêtre de ±60 s autour de l'horloge du Mac.
        let ecart = abs(dateReferenceMac.timeIntervalSince(evenement.horodatage))
        guard ecart <= Self.toleranceHorodatageSecondes else {
            throw ErreurEvenementSigneCrypto.horodatageHorsTolerance(ecartSecondes: Int(ecart.rounded()))
        }

        // 8. Toutes les vérifications ont réussi : mise à jour atomique de l'état anti-rejeu en RAM.
        dernierCompteurAccepte = evenement.compteur
        enregistrerNonceAccepte(evenement.nonce)

        return evenement.alerte
    }

    public func dechiffrerEtVerifierEvenement(
        blocChiffreAESGCM: Data,
        via canalChiffre: ServiceCanalChiffreCryptoProtocol,
        dateReferenceMac: Date = Date()
    ) throws -> Alerte {
        // 1. Déchiffrement et vérification du tag d'intégrité AES-256-GCM (MAC-3 : contre I1 et T1).
        let octetsEvenementClair = try canalChiffre.dechiffrerMessageDepuisIPhone(blocChiffreAESGCM)

        // 2. Désérialisation JSON de l'EvenementAlerteSigne (sans ! ni try!).
        let evenement = try Self.decoderEvenementSigne(depuis: octetsEvenementClair)

        // 3. Vérification de la signature P-256 ECDSA et des 3 règles anti-rejeu (MAC-4 : contre S2, R1, T1, T2).
        return try verifierEtAccepterEvenement(evenement, dateReferenceMac: dateReferenceMac)
    }

    public func reinitialiserEtatAntiRejeu() {
        dernierCompteurAccepte = 0
        noncesAcceptes.removeAll()
        ordreNoncesAcceptes.removeAll()
    }

    // MARK: - Construction, signature et sérialisation côté iPhone (et tests)

    /// Crée et signe un `EvenementAlerteSigne` à l'aide d'un signataire P-256 (Secure Enclave sur iPhone ou clé mémoire en test).
    ///
    /// - Parameters:
    ///   - alerte: L'alerte de sécurité à transmettre au Mac.
    ///   - compteur: Le compteur strictement croissant de la session (`>= 1`).
    ///   - nonce: Un nonce aléatoire de 16 octets (généré par CryptoKit par défaut).
    ///   - horodatage: L'horodatage d'émission (`Date()` par défaut).
    ///   - signataire: Le signataire P-256 (`SignataireSecureEnclaveP256` ou `SignataireMemoireP256`).
    /// - Returns: L'`EvenementAlerteSigne` prêt à être sérialisé et chiffré en `AES-256-GCM`.
    public static func creerEvenementSigne(
        alerte: Alerte,
        compteur: UInt64,
        nonce: Data = ServiceAppairageCrypto.genererNonce16Octets(),
        horodatage: Date = Date(),
        signataire: SignataireEvenementP256Protocol
    ) throws -> EvenementAlerteSigne {
        do {
            try alerte.validerFormat()
        } catch let erreurValidation as ErreurValidationAlerte {
            throw ErreurEvenementSigneCrypto.alerteInvalide(erreurValidation)
        } catch {
            throw ErreurEvenementSigneCrypto.formatJSONInvalide
        }

        guard nonce.count == EvenementAlerteSigne.tailleNonceOctets else {
            throw ErreurEvenementSigneCrypto.tailleNonceInvalide(nonce.count)
        }

        let donneesCanoniques = construireDonneesCanoniquesASigner(
            alerte: alerte,
            compteur: compteur,
            nonce: nonce,
            horodatage: horodatage
        )
        let signature = try signataire.signer(donneesCanoniques)

        return EvenementAlerteSigne(
            alerte: alerte,
            compteur: compteur,
            nonce: nonce,
            horodatage: horodatage,
            signatureECDSA: signature.rawRepresentation
        )
    }

    /// Encode un `EvenementAlerteSigne` en JSON puis le chiffre en `AES-256-GCM` avec la clé `iPhone → Mac` (`MAC-3` + `MAC-4`).
    public static func encoderEtChiffrerEvenementCoteIPhone(
        evenement: EvenementAlerteSigne,
        cleSessionIPhoneVersMac: SymmetricKey
    ) throws -> Data {
        let octetsJSON = try encoderEvenementSigne(evenement)
        return try ServiceCanalChiffreCrypto.chiffrerAESGCM(
            donneesClaires: octetsJSON,
            cle: cleSessionIPhoneVersMac,
            donneesAssociees: ServiceCanalChiffreCrypto.aadDirectionIPhoneVersMac
        )
    }

    /// Sérialise un `EvenementAlerteSigne` en JSON ISO-8601.
    public static func encoderEvenementSigne(_ evenement: EvenementAlerteSigne) throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        encodeur.outputFormatting = [.sortedKeys]
        do {
            return try encodeur.encode(evenement)
        } catch {
            throw ErreurEvenementSigneCrypto.formatJSONInvalide
        }
    }

    /// Désérialise un `EvenementAlerteSigne` depuis sa représentation JSON en vérifiant la taille maximale (64 Ko).
    public static func decoderEvenementSigne(depuis donnees: Data) throws -> EvenementAlerteSigne {
        guard !donnees.isEmpty,
              donnees.count <= ServiceCanalChiffreCrypto.tailleMaximaleMessage else {
            throw ErreurEvenementSigneCrypto.formatJSONInvalide
        }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        do {
            return try decodeur.decode(EvenementAlerteSigne.self, from: donnees)
        } catch {
            throw ErreurEvenementSigneCrypto.formatJSONInvalide
        }
    }

    /// Construit la représentation binaire canonique et déterministe signée par l'iPhone et vérifiée par le Mac.
    ///
    /// Pourquoi ne pas signer directement le JSON brut ? Parce que le formatage JSON (espaces, ordre des clés,
    /// décimales de `Date`) peut varier d'un encodeur à l'autre. Construire un tampon binaire canonique
    /// garantit un déterminisme octet par octet et couvre chaque champ sans ambiguïté :
    /// ```
    /// "antitracker-evenement-alerte-v1"
    /// || compteur (8 octets UInt64 Big-Endian)
    /// || nonce (16 octets)
    /// || horodatageSecondesUnix (8 octets Int64 Big-Endian)
    /// || alerte.id (16 octets UUID)
    /// || alerte.niveau.rawValue (UTF-8)
    /// || alerte.idHache (32 octets HMAC-SHA256)
    /// || nombreBalayagesRefs (4 octets UInt32 Big-Endian)
    /// || chaque UUID de balayagesRefs (16 octets chacun)
    /// || alerte.dateSecondesUnix (8 octets Int64 Big-Endian)
    /// ```
    public static func construireDonneesCanoniquesASigner(
        alerte: Alerte,
        compteur: UInt64,
        nonce: Data,
        horodatage: Date
    ) -> Data {
        var tampon = Data(contexteSignatureEvenement.utf8)

        // 1. Compteur (8 octets Big-Endian)
        var compteurBE = compteur.bigEndian
        tampon.append(Data(bytes: &compteurBE, count: MemoryLayout<UInt64>.size))

        // 2. Nonce (16 octets)
        tampon.append(nonce)

        // 3. Horodatage de l'événement (secondes Unix entières sur 8 octets Big-Endian)
        var horodatageSecondesBE = Int64(horodatage.timeIntervalSince1970.rounded()).bigEndian
        tampon.append(Data(bytes: &horodatageSecondesBE, count: MemoryLayout<Int64>.size))

        // 4. Identifiant de l'alerte (16 octets UUID)
        withUnsafeBytes(of: alerte.id.uuid) { octetsUUID in
            tampon.append(contentsOf: octetsUUID)
        }

        // 5. Niveau de l'alerte
        tampon.append(Data(alerte.niveau.rawValue.utf8))

        // 6. Condensat HMAC-SHA256 de l'appareil (32 octets)
        tampon.append(alerte.idHache)

        // 7. Nombre et liste des UUID de balayages de référence
        var nombreRefsBE = UInt32(clamping: alerte.balayagesRefs.count).bigEndian
        tampon.append(Data(bytes: &nombreRefsBE, count: MemoryLayout<UInt32>.size))
        for idBalayage in alerte.balayagesRefs {
            withUnsafeBytes(of: idBalayage.uuid) { octetsUUID in
                tampon.append(contentsOf: octetsUUID)
            }
        }

        // 8. Date de l'alerte (secondes Unix entières sur 8 octets Big-Endian)
        var dateAlerteSecondesBE = Int64(alerte.date.timeIntervalSince1970.rounded()).bigEndian
        tampon.append(Data(bytes: &dateAlerteSecondesBE, count: MemoryLayout<Int64>.size))

        return tampon
    }

    // MARK: - Aide interne de gestion bornée des nonces en RAM

    private func enregistrerNonceAccepte(_ nonce: Data) {
        noncesAcceptes.insert(nonce)
        ordreNoncesAcceptes.append(nonce)

        if ordreNoncesAcceptes.count > Self.nombreMaxNoncesEnMemoire {
            let plusAncien = ordreNoncesAcceptes.removeFirst()
            noncesAcceptes.remove(plusAncien)
        }
    }
}
#endif
