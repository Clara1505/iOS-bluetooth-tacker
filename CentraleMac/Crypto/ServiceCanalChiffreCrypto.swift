#if canImport(CryptoKit)
import Foundation
import CryptoKit

// MARK: - Modèles et erreurs du canal chiffré (MAC-3, étiquette `crypto` -> relecture Aïda obligatoire)

/// État du canal chiffré entre l'iPhone capteur et la centrale Mac (`MAC-3`).
///
/// Conforme à `CLAUDE.md` (§6) et `docs/securite/CHOIX_CRYPTO.md` (§3.2) :
/// - Le canal ne peut s'ouvrir que si un appairage `MAC-2` est actif et confirmé (`E2`).
/// - En cas d'erreur de signature, de dérivation ou de déchiffrement, le canal échoue en sécurité (`.verrouille`).
public enum EtatCanalChiffreMac: Equatable, Sendable {
    /// Aucune session chiffrée active (clés absentes ou purgées).
    case ferme
    /// L'échange ECDH éphémère signé et la dérivation HKDF-SHA256 ont réussi : les 2 clés directionnelles sont en RAM.
    case ouvert(empreinteSessionHex: String)
    /// Le canal a été verrouillé suite à une erreur de sécurité (signature ECDH invalide, tag AES-GCM refusé, pair non appairé).
    case verrouille(raison: String)
}

/// Erreurs cryptographiques du canal chiffré (`MAC-3`).
///
/// Menaces STRIDE couvertes :
/// - `S1` : Homme du milieu sur l'échange ECDH (`signatureEphemeralInvalide`, `pairNonAppaire`).
/// - `I1` : Interception du trafic réseau (`canalNonOuvert`, confidentialité persistante par ECDH éphémère + HKDF).
/// - `T1` : Altération d'un message en transit (`integriteOuDechiffrementAESGCMEchoue`, `messageChiffreTropCourt`).
/// - `E2` : Tentative d'ouverture de canal par un appareil non appairé (`pairNonAppaire`).
public enum ErreurCanalChiffreCrypto: Error, Equatable, Sendable {
    /// Aucun iPhone n'est appairé et confirmé dans `ServiceAppairageCrypto` (`MAC-2`, menace `E2`).
    case pairNonAppaire
    /// La clé publique ECDH éphémère P-256 ne mesure pas 64 octets ou n'est pas un point valide sur la courbe P-256.
    case clePubliqueEphemeralInvalide
    /// La signature ECDSA P-256 couvrant la clé publique ECDH éphémère est invalide (`S1`).
    case signatureEphemeralInvalide
    /// L'accord de clé Diffie-Hellman sur courbe elliptique (ECDH P-256) a échoué.
    case accordECDHImpossible
    /// Le canal chiffré n'est pas dans l'état `.ouvert` (`I1`, `E2`).
    case canalNonOuvert
    /// La charge utile claire fournie au chiffrement est vide ou dépasse le plafond de 64 Ko (`D2`, `D3`).
    case tailleMessageClairInvalide(Int)
    /// Le bloc AES-GCM combiné est plus court que la taille minimale (`12` octets de nonce + `16` octets de tag = `28` octets) ou dépasse 64 Ko (`T1`, `D3`).
    case tailleMessageChiffreInvalide(Int)
    /// La vérification du tag d'authentification AES-256-GCM ou le déchiffrement a échoué (`T1`, `I1`, ou attaque par réflexion).
    case integriteOuDechiffrementAESGCMEchoue
}

/// Message réseau envoyé par l'iPhone au Mac pour initier l'ouverture du canal chiffré (`MAC-3`).
///
/// Contient la clé publique ECDH P-256 éphémère de l'iPhone (64 octets) et la signature ECDSA P-256
/// produite par la clé d'identité de l'iPhone (Secure Enclave) sur :
/// `"antitracker-ecdh-iphone-v1" || clePubliqueEphemeralIPhone (64 o) || clePubliqueIdentiteMac (64 o)`.
public struct MessageEchangeECDHIPhone: Codable, Equatable, Sendable {
    /// Taille exacte de la représentation brute (`rawRepresentation`) d'une clé publique P-256 (64 octets : X || Y).
    public static let tailleClePubliqueP256Brute = 64

    /// Clé publique ECDH P-256 éphémère de l'iPhone (`rawRepresentation`, 64 octets).
    public let clePubliqueEphemeralIPhoneBrute: Data
    /// Signature ECDSA P-256 (`rawRepresentation`) signée par la clé d'identité de l'iPhone.
    public let signatureIdentiteIPhone: Data

    public init(
        clePubliqueEphemeralIPhoneBrute: Data,
        signatureIdentiteIPhone: Data
    ) {
        self.clePubliqueEphemeralIPhoneBrute = clePubliqueEphemeralIPhoneBrute
        self.signatureIdentiteIPhone = signatureIdentiteIPhone
    }
}

/// Réponse réseau du Mac envoyée à l'iPhone pour finaliser l'ouverture du canal chiffré (`MAC-3`).
///
/// Contient la clé publique ECDH P-256 éphémère du Mac (64 octets) et la signature ECDSA P-256
/// produite par la clé d'identité du Mac sur :
/// `"antitracker-ecdh-mac-v1" || clePubliqueEphemeralMac (64 o) || clePubliqueEphemeralIPhone (64 o) || clePubliqueIdentiteIPhone (64 o)`.
public struct ReponseEchangeECDHMac: Codable, Equatable, Sendable {
    /// Clé publique ECDH P-256 éphémère du Mac (`rawRepresentation`, 64 octets).
    public let clePubliqueEphemeralMacBrute: Data
    /// Signature ECDSA P-256 (`rawRepresentation`) signée par la clé d'identité du Mac.
    public let signatureIdentiteMac: Data

    public init(
        clePubliqueEphemeralMacBrute: Data,
        signatureIdentiteMac: Data
    ) {
        self.clePubliqueEphemeralMacBrute = clePubliqueEphemeralMacBrute
        self.signatureIdentiteMac = signatureIdentiteMac
    }
}

// MARK: - Protocole du service de canal chiffré (`CLAUDE.md` §7)

/// Contrat abstrait du service de canal chiffré (`MAC-3`).
public protocol ServiceCanalChiffreCryptoProtocol: AnyObject {
    /// État courant du canal chiffré.
    var etat: EtatCanalChiffreMac { get }
    /// Indique si le canal est ouvert et dispose de ses clés de session AES-256 en RAM.
    var estOuvert: Bool { get }

    /// Traite le message d'échange ECDH signé de l'iPhone appairé, génère la paire ECDH éphémère du Mac,
    /// dérive les deux clés symétriques directionnelles via `HKDF-SHA256` et retourne la réponse signée du Mac.
    ///
    /// - Parameter messageIPhone: Clé publique ECDH éphémère de l'iPhone et sa signature ECDSA P-256.
    /// - Returns: La réponse signée du Mac (`ReponseEchangeECDHMac`).
    /// - Throws: `ErreurCanalChiffreCrypto` si l'iPhone n'est pas appairé ou si la signature est invalide.
    func etablirCanalDepuisMessageIPhone(_ messageIPhone: MessageEchangeECDHIPhone) throws -> ReponseEchangeECDHMac

    /// Déchiffre et vérifie l'intégrité d'un message envoyé par l'iPhone vers le Mac avec la clé `cleIPhoneVersMac` (`AES-256-GCM`).
    ///
    /// - Parameter donneesCombinees: Le bloc AES-GCM combiné (`nonce 12 o || texte chiffré || tag 16 o`).
    /// - Returns: Les octets déchiffrés et authentifiés.
    /// - Throws: `ErreurCanalChiffreCrypto` si le canal n'est pas ouvert ou si un seul bit a été altéré (`T1`).
    func dechiffrerMessageDepuisIPhone(_ donneesCombinees: Data) throws -> Data

    /// Chiffre et authentifie un message envoyé par le Mac vers l'iPhone avec la clé `cleMacVersIPhone` (`AES-256-GCM`).
    ///
    /// - Parameter donneesClaires: Les octets en clair à chiffrer.
    /// - Returns: Le bloc AES-GCM combiné avec un nonce aléatoire généré par CryptoKit.
    /// - Throws: `ErreurCanalChiffreCrypto` si le canal n'est pas ouvert ou si la taille est invalide.
    func chiffrerMessageVersIPhone(_ donneesClaires: Data) throws -> Data

    /// Efface immédiatement de la mémoire vive (RAM) les clés de session AES-256 et referme le canal (`MAC-7`, `I4`).
    func purgerCanalEnMemoire()
}

// MARK: - Implémentation CryptoKit du canal chiffré (MAC-3)

/// Implémentation cryptographique du canal chiffré iPhone ↔ Mac (`MAC-3`).
///
/// Conforme à `CLAUDE.md` (§6 et §7) et `docs/securite/CHOIX_CRYPTO.md` (§3.2 et §4) :
/// - **CryptoKit uniquement** : `P256.KeyAgreement`, `P256.Signing`, `HKDF<SHA256>`, `AES.GCM`.
/// - **Confidentialité persistante (`I1`)** : clés ECDH P-256 éphémères renouvelées à chaque session et détruites aussitôt les clés AES dérivées.
/// - **Authentification de l'échange (`S1`)** : chaque clé publique ECDH éphémère est signée par la clé d'identité appairée en `MAC-2`.
/// - **Deux clés directionnelles (`HKDF-SHA256`)** : une clé `iPhone → Mac` et une clé `Mac → iPhone` dérivées avec deux `info` distincts
///   incluant les clés publiques échangées, empêchant toute attaque par réflexion.
/// - **Nonce aléatoire (`AES-256-GCM`)** : aucun nonce fixe n'est jamais passé à `AES.GCM.seal` ; CryptoKit génère un nonce neuf à chaque message.
public final class ServiceCanalChiffreCrypto: ServiceCanalChiffreCryptoProtocol {
    /// Contexte de séparation de domaine pour la signature de la clé ECDH éphémère côté iPhone.
    public static let contexteSignatureECDHIPhone = "antitracker-ecdh-iphone-v1"
    /// Contexte de séparation de domaine pour la signature de la clé ECDH éphémère côté Mac.
    public static let contexteSignatureECDHMac = "antitracker-ecdh-mac-v1"
    /// Sel fixe et documenté pour l'extraction HKDF-SHA256 (`CHOIX_CRYPTO.md` §3.2).
    public static let selHKDFProtocole = Data("antitracker-hkdf-sel-v1".utf8)
    /// Préfixe du champ `info` HKDF pour la clé de chiffrement dans le sens `iPhone → Mac`.
    public static let prefixeInfoIPhoneVersMac = "antitracker-canal-v1-i2m"
    /// Préfixe du champ `info` HKDF pour la clé de chiffrement dans le sens `Mac → iPhone`.
    public static let prefixeInfoMacVersIPhone = "antitracker-canal-v1-m2i"
    /// Taille minimale d'un bloc combiné AES-GCM : 12 octets de nonce standard + 16 octets de tag GCM + au moins 1 octet chiffré = 29 octets.
    public static let tailleMinimaleBlocAESGCM = 29
    /// Taille maximale autorisée d'un message sur le canal (64 Ko, alignée sur `CadrageTrameTCP.tailleMaxMessage`, `ARCH-2`).
    public static let tailleMaximaleMessage = 65_536
    /// Données associées authentifiées (AAD) liant chaque bloc AES-GCM à sa direction pour bloquer toute réflexion inter-direction.
    public static let aadDirectionIPhoneVersMac = Data("antitracker-aad-i2m-v1".utf8)
    /// Données associées authentifiées (AAD) pour le sens `Mac → iPhone`.
    public static let aadDirectionMacVersIPhone = Data("antitracker-aad-m2i-v1".utf8)

    /// État courant du canal chiffré.
    public private(set) var etat: EtatCanalChiffreMac = .ferme

    /// Référence au service d'appairage (`MAC-2`) fournissant les clés d'identité vérifiées en RAM.
    private let serviceAppairage: ServiceAppairageCryptoProtocol
    /// Clé symétrique AES-256 utilisée uniquement pour déchiffrer les messages `iPhone → Mac` (en RAM).
    private var cleSessionIPhoneVersMac: SymmetricKey?
    /// Clé symétrique AES-256 utilisée uniquement pour chiffrer les messages `Mac → iPhone` (en RAM).
    private var cleSessionMacVersIPhone: SymmetricKey?

    public var estOuvert: Bool {
        if case .ouvert = etat,
           cleSessionIPhoneVersMac != nil,
           cleSessionMacVersIPhone != nil {
            return true
        }
        return false
    }

    /// Initialise le service de canal chiffré en le liant au service d'appairage `MAC-2`.
    ///
    /// - Parameter serviceAppairage: Service d'appairage détenant la clé d'identité du Mac et la clé publique appairée de l'iPhone.
    public init(serviceAppairage: ServiceAppairageCryptoProtocol) {
        self.serviceAppairage = serviceAppairage
    }

    // MARK: - Étape 1 : Échange de clés ECDH P-256 éphémères signées et dérivation HKDF-SHA256

    public func etablirCanalDepuisMessageIPhone(
        _ messageIPhone: MessageEchangeECDHIPhone
    ) throws -> ReponseEchangeECDHMac {
        // Toujours repartir d'un état propre avant d'ouvrir une nouvelle session.
        purgerCanalEnMemoire()

        // 1. Vérifier que l'appairage MAC-2 est bien actif et confirmé par l'utilisateur (contre E2).
        guard serviceAppairage.estAppaire,
              let cleIdentiteIPhone = serviceAppairage.clePubliqueIPhoneAppaire,
              let cleIdentiteMac = serviceAppairage.clePubliqueIdentiteMac else {
            verrouillerEnSecurite(raison: "Ouverture de canal refusée : aucun iPhone appairé.")
            throw ErreurCanalChiffreCrypto.pairNonAppaire
        }

        // 2. Valider la taille (64 octets) et reconstruire la clé publique ECDH P-256 éphémère de l'iPhone.
        guard messageIPhone.clePubliqueEphemeralIPhoneBrute.count == MessageEchangeECDHIPhone.tailleClePubliqueP256Brute else {
            verrouillerEnSecurite(raison: "Taille de clé ECDH éphémère iPhone invalide.")
            throw ErreurCanalChiffreCrypto.clePubliqueEphemeralInvalide
        }
        let clePubliqueEphemeralIPhone: P256.KeyAgreement.PublicKey
        do {
            clePubliqueEphemeralIPhone = try P256.KeyAgreement.PublicKey(
                rawRepresentation: messageIPhone.clePubliqueEphemeralIPhoneBrute
            )
        } catch {
            verrouillerEnSecurite(raison: "Clé publique ECDH P-256 iPhone malformée.")
            throw ErreurCanalChiffreCrypto.clePubliqueEphemeralInvalide
        }

        // 3. Vérifier la signature ECDSA P-256 de l'iPhone sur sa clé éphémère (bloque tout homme du milieu S1).
        let signatureIPhone: P256.Signing.ECDSASignature
        do {
            signatureIPhone = try P256.Signing.ECDSASignature(
                rawRepresentation: messageIPhone.signatureIdentiteIPhone
            )
        } catch {
            verrouillerEnSecurite(raison: "Format de signature ECDH iPhone invalide.")
            throw ErreurCanalChiffreCrypto.signatureEphemeralInvalide
        }

        let donneesSigneesParIPhone = Self.construireDonneesSignatureECDHIPhone(
            clePubliqueEphemeralIPhoneBrute: clePubliqueEphemeralIPhone.rawRepresentation,
            clePubliqueIdentiteMacBrute: cleIdentiteMac.rawRepresentation
        )

        guard cleIdentiteIPhone.isValidSignature(signatureIPhone, for: donneesSigneesParIPhone) else {
            verrouillerEnSecurite(raison: "Signature de la clé ECDH éphémère iPhone invalide.")
            throw ErreurCanalChiffreCrypto.signatureEphemeralInvalide
        }

        // 4. Générer la paire de clés ECDH P-256 éphémère du Mac (en pile locale uniquement : détruite dès la fin de cette fonction).
        let clePriveeEphemeralMac = P256.KeyAgreement.PrivateKey()
        let clePubliqueEphemeralMacBrute = clePriveeEphemeralMac.publicKey.rawRepresentation

        // 5. Signer la clé publique ECDH éphémère du Mac avec la clé d'identité du Mac (liée à la clé éphémère de l'iPhone).
        let donneesASignerParMac = Self.construireDonneesSignatureECDHMac(
            clePubliqueEphemeralMacBrute: clePubliqueEphemeralMacBrute,
            clePubliqueEphemeralIPhoneBrute: clePubliqueEphemeralIPhone.rawRepresentation,
            clePubliqueIdentiteIPhoneBrute: cleIdentiteIPhone.rawRepresentation
        )

        let signatureMac: P256.Signing.ECDSASignature
        do {
            signatureMac = try serviceAppairage.signerAvecIdentiteMac(donneesASignerParMac)
        } catch {
            verrouillerEnSecurite(raison: "Impossible de signer la clé ECDH éphémère du Mac.")
            throw ErreurCanalChiffreCrypto.signatureEphemeralInvalide
        }

        // 6. Calculer le secret partagé ECDH P-256 et dériver les 2 clés directionnelles AES-256 via HKDF-SHA256.
        let clesDerivees: (cleIPhoneVersMac: SymmetricKey, cleMacVersIPhone: SymmetricKey, empreinteSessionHex: String)
        do {
            clesDerivees = try Self.deriverClesSessionBidirectionnelles(
                clePriveeEphemeralLocale: clePriveeEphemeralMac,
                clePubliqueEphemeralDistante: clePubliqueEphemeralIPhone,
                clePubliqueEphemeralIPhoneBrute: clePubliqueEphemeralIPhone.rawRepresentation,
                clePubliqueEphemeralMacBrute: clePubliqueEphemeralMacBrute
            )
        } catch {
            verrouillerEnSecurite(raison: "Échec de l'accord ECDH ou de la dérivation HKDF.")
            throw ErreurCanalChiffreCrypto.accordECDHImpossible
        }

        // 7. Enregistrer les deux clés de session AES-256 en RAM et ouvrir le canal.
        self.cleSessionIPhoneVersMac = clesDerivees.cleIPhoneVersMac
        self.cleSessionMacVersIPhone = clesDerivees.cleMacVersIPhone
        self.etat = .ouvert(empreinteSessionHex: clesDerivees.empreinteSessionHex)

        return ReponseEchangeECDHMac(
            clePubliqueEphemeralMacBrute: clePubliqueEphemeralMacBrute,
            signatureIdentiteMac: signatureMac.rawRepresentation
        )
    }

    // MARK: - Étape 2 : Chiffrement et déchiffrement authentifiés AES-256-GCM

    public func dechiffrerMessageDepuisIPhone(_ donneesCombinees: Data) throws -> Data {
        guard estOuvert, let cleReception = cleSessionIPhoneVersMac else {
            throw ErreurCanalChiffreCrypto.canalNonOuvert
        }
        return try Self.dechiffrerAESGCM(
            donneesCombinees: donneesCombinees,
            cle: cleReception,
            donneesAssociees: Self.aadDirectionIPhoneVersMac
        )
    }

    public func chiffrerMessageVersIPhone(_ donneesClaires: Data) throws -> Data {
        guard estOuvert, let cleEmission = cleSessionMacVersIPhone else {
            throw ErreurCanalChiffreCrypto.canalNonOuvert
        }
        return try Self.chiffrerAESGCM(
            donneesClaires: donneesClaires,
            cle: cleEmission,
            donneesAssociees: Self.aadDirectionMacVersIPhone
        )
    }

    // MARK: - Étape 3 : Purge en mémoire vive (MAC-7, I4)

    public func purgerCanalEnMemoire() {
        cleSessionIPhoneVersMac = nil
        cleSessionMacVersIPhone = nil
        etat = .ferme
    }

    // MARK: - Fonctions cryptographiques statiques (partagées entre iPhone et Mac pour le handshake et AES-GCM)

    /// Construit le bloc canonique signé par l'iPhone lors de l'envoi de sa clé publique ECDH éphémère.
    ///
    /// Format : `"antitracker-ecdh-iphone-v1" || cleEphIPhone (64 o) || cleIdentiteMac (64 o)`.
    public static func construireDonneesSignatureECDHIPhone(
        clePubliqueEphemeralIPhoneBrute: Data,
        clePubliqueIdentiteMacBrute: Data
    ) -> Data {
        var tampon = Data(contexteSignatureECDHIPhone.utf8)
        tampon.append(clePubliqueEphemeralIPhoneBrute)
        tampon.append(clePubliqueIdentiteMacBrute)
        return tampon
    }

    /// Construit le bloc canonique signé par le Mac lors de l'envoi de sa clé publique ECDH éphémère.
    ///
    /// Format : `"antitracker-ecdh-mac-v1" || cleEphMac (64 o) || cleEphIPhone (64 o) || cleIdentiteIPhone (64 o)`.
    public static func construireDonneesSignatureECDHMac(
        clePubliqueEphemeralMacBrute: Data,
        clePubliqueEphemeralIPhoneBrute: Data,
        clePubliqueIdentiteIPhoneBrute: Data
    ) -> Data {
        var tampon = Data(contexteSignatureECDHMac.utf8)
        tampon.append(clePubliqueEphemeralMacBrute)
        tampon.append(clePubliqueEphemeralIPhoneBrute)
        tampon.append(clePubliqueIdentiteIPhoneBrute)
        return tampon
    }

    /// Calcule le secret partagé ECDH P-256 et dérive deux clés `AES-256` distinctes via `HKDF-SHA256`
    /// (`CHOIX_CRYPTO.md` §3.2 : une clé par sens avec deux valeurs de `info` différentes).
    ///
    /// - Parameters:
    ///   - clePriveeEphemeralLocale: Clé privée ECDH éphémère du côté local (iPhone ou Mac).
    ///   - clePubliqueEphemeralDistante: Clé publique ECDH éphémère vérifiée de l'autre côté.
    ///   - clePubliqueEphemeralIPhoneBrute: Représentation brute (64 octets) de la clé ECDH de l'iPhone.
    ///   - clePubliqueEphemeralMacBrute: Représentation brute (64 octets) de la clé ECDH du Mac.
    /// - Returns: Le couple `(cleIPhoneVersMac, cleMacVersIPhone, empreinteSessionHex)`.
    public static func deriverClesSessionBidirectionnelles(
        clePriveeEphemeralLocale: P256.KeyAgreement.PrivateKey,
        clePubliqueEphemeralDistante: P256.KeyAgreement.PublicKey,
        clePubliqueEphemeralIPhoneBrute: Data,
        clePubliqueEphemeralMacBrute: Data
    ) throws -> (cleIPhoneVersMac: SymmetricKey, cleMacVersIPhone: SymmetricKey, empreinteSessionHex: String) {
        // 1. Accord de clé ECDH P-256.
        let secretPartage: SharedSecret
        do {
            secretPartage = try clePriveeEphemeralLocale.sharedSecretFromKeyAgreement(
                with: clePubliqueEphemeralDistante
            )
        } catch {
            throw ErreurCanalChiffreCrypto.accordECDHImpossible
        }

        // 2. Construction des contextes `info` liant les clés dérivées aux deux clés publiques éphémères de la session.
        var infoIPhoneVersMac = Data(prefixeInfoIPhoneVersMac.utf8)
        infoIPhoneVersMac.append(clePubliqueEphemeralIPhoneBrute)
        infoIPhoneVersMac.append(clePubliqueEphemeralMacBrute)

        var infoMacVersIPhone = Data(prefixeInfoMacVersIPhone.utf8)
        infoMacVersIPhone.append(clePubliqueEphemeralIPhoneBrute)
        infoMacVersIPhone.append(clePubliqueEphemeralMacBrute)

        // 3. Dérivation HKDF-SHA256 en deux clés symétriques distinctes de 256 bits (32 octets).
        let cleIPhoneVersMac = secretPartage.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: selHKDFProtocole,
            sharedInfo: infoIPhoneVersMac,
            outputByteCount: 32
        )

        let cleMacVersIPhone = secretPartage.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: selHKDFProtocole,
            sharedInfo: infoMacVersIPhone,
            outputByteCount: 32
        )

        // 4. Calcul d'un identifiant public non sensible de session (4 premiers octets du SHA-256 des 2 clés publiques éphémères).
        var transcriptPublic = Data()
        transcriptPublic.append(clePubliqueEphemeralIPhoneBrute)
        transcriptPublic.append(clePubliqueEphemeralMacBrute)
        let hashSession = Data(SHA256.hash(data: transcriptPublic))
        let empreinteSessionHex = hashSession.prefix(4).map { String(format: "%02X", $0) }.joined()

        return (cleIPhoneVersMac, cleMacVersIPhone, empreinteSessionHex)
    }

    /// Vérifie côté iPhone la réponse ECDH du Mac et dérive la paire de clés de session (`MAC-3`).
    ///
    /// - Parameters:
    ///   - reponseMac: La réponse ECDH signée reçue du Mac.
    ///   - clePriveeEphemeralIPhone: La clé privée ECDH éphémère générée par l'iPhone pour cette session.
    ///   - clePubliqueIdentiteMac: La clé publique d'identité du Mac vérifiée lors de l'appairage `MAC-2`.
    ///   - clePubliqueIdentiteIPhoneBrute: La représentation brute (64 octets) de la clé d'identité de l'iPhone.
    /// - Returns: Les deux clés symétriques directionnelles `(cleIPhoneVersMac, cleMacVersIPhone)` et l'empreinte de session.
    public static func finaliserCanalCoteIPhone(
        reponseMac: ReponseEchangeECDHMac,
        clePriveeEphemeralIPhone: P256.KeyAgreement.PrivateKey,
        clePubliqueIdentiteMac: P256.Signing.PublicKey,
        clePubliqueIdentiteIPhoneBrute: Data
    ) throws -> (cleIPhoneVersMac: SymmetricKey, cleMacVersIPhone: SymmetricKey, empreinteSessionHex: String) {
        guard reponseMac.clePubliqueEphemeralMacBrute.count == MessageEchangeECDHIPhone.tailleClePubliqueP256Brute else {
            throw ErreurCanalChiffreCrypto.clePubliqueEphemeralInvalide
        }
        let clePubliqueEphemeralMac: P256.KeyAgreement.PublicKey
        do {
            clePubliqueEphemeralMac = try P256.KeyAgreement.PublicKey(
                rawRepresentation: reponseMac.clePubliqueEphemeralMacBrute
            )
        } catch {
            throw ErreurCanalChiffreCrypto.clePubliqueEphemeralInvalide
        }

        let signatureMac: P256.Signing.ECDSASignature
        do {
            signatureMac = try P256.Signing.ECDSASignature(
                rawRepresentation: reponseMac.signatureIdentiteMac
            )
        } catch {
            throw ErreurCanalChiffreCrypto.signatureEphemeralInvalide
        }

        let clePubliqueEphemeralIPhoneBrute = clePriveeEphemeralIPhone.publicKey.rawRepresentation
        let donneesSigneesParMac = construireDonneesSignatureECDHMac(
            clePubliqueEphemeralMacBrute: clePubliqueEphemeralMac.rawRepresentation,
            clePubliqueEphemeralIPhoneBrute: clePubliqueEphemeralIPhoneBrute,
            clePubliqueIdentiteIPhoneBrute: clePubliqueIdentiteIPhoneBrute
        )

        guard clePubliqueIdentiteMac.isValidSignature(signatureMac, for: donneesSigneesParMac) else {
            throw ErreurCanalChiffreCrypto.signatureEphemeralInvalide
        }

        return try deriverClesSessionBidirectionnelles(
            clePriveeEphemeralLocale: clePriveeEphemeralIPhone,
            clePubliqueEphemeralDistante: clePubliqueEphemeralMac,
            clePubliqueEphemeralIPhoneBrute: clePubliqueEphemeralIPhoneBrute,
            clePubliqueEphemeralMacBrute: clePubliqueEphemeralMac.rawRepresentation
        )
    }

    /// Chiffre un message avec `AES-256-GCM` en laissant CryptoKit générer un nonce aléatoire neuf (`CHOIX_CRYPTO.md` §3.2).
    ///
    /// - Parameters:
    ///   - donneesClaires: Les octets à chiffrer (entre 1 et 65 536 octets).
    ///   - cle: La clé symétrique directionnelle de 256 bits.
    ///   - donneesAssociees: Données associées authentifiées (AAD) liant le message à sa direction.
    /// - Returns: Le bloc combiné `nonce (12 o) || texte chiffré || tag GCM (16 o)`.
    public static func chiffrerAESGCM(
        donneesClaires: Data,
        cle: SymmetricKey,
        donneesAssociees: Data
    ) throws -> Data {
        guard !donneesClaires.isEmpty, donneesClaires.count <= tailleMaximaleMessage else {
            throw ErreurCanalChiffreCrypto.tailleMessageClairInvalide(donneesClaires.count)
        }

        // Aucun paramètre `nonce:` n'est fourni : CryptoKit génère automatiquement un AES.GCM.Nonce aléatoire de 12 octets.
        let boiteScellee: AES.GCM.SealedBox
        do {
            boiteScellee = try AES.GCM.seal(
                donneesClaires,
                using: cle,
                authenticating: donneesAssociees
            )
        } catch {
            throw ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue
        }

        guard let donneesCombinees = boiteScellee.combined else {
            throw ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue
        }
        return donneesCombinees
    }

    /// Vérifie le tag d'authentification GCM et déchiffre un bloc combiné `AES-256-GCM`.
    ///
    /// Toute modification d'un seul bit du nonce, du chiffré, du tag ou de la direction (AAD)
    /// fait échouer `AES.GCM.open` et lève `.integriteOuDechiffrementAESGCMEchoue` (`T1`, `I1`).
    ///
    /// - Parameters:
    ///   - donneesCombinees: Le bloc combiné `nonce (12 o) || chiffré || tag (16 o)`.
    ///   - cle: La clé symétrique directionnelle de 256 bits attendue à la réception.
    ///   - donneesAssociees: Données associées authentifiées (AAD) de la direction attendue.
    /// - Returns: Les octets en clair authentifiés.
    public static func dechiffrerAESGCM(
        donneesCombinees: Data,
        cle: SymmetricKey,
        donneesAssociees: Data
    ) throws -> Data {
        guard donneesCombinees.count >= tailleMinimaleBlocAESGCM,
              donneesCombinees.count <= tailleMaximaleMessage else {
            throw ErreurCanalChiffreCrypto.tailleMessageChiffreInvalide(donneesCombinees.count)
        }

        let boiteScellee: AES.GCM.SealedBox
        do {
            boiteScellee = try AES.GCM.SealedBox(combined: donneesCombinees)
        } catch {
            throw ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue
        }

        do {
            return try AES.GCM.open(
                boiteScellee,
                using: cle,
                authenticating: donneesAssociees
            )
        } catch {
            throw ErreurCanalChiffreCrypto.integriteOuDechiffrementAESGCMEchoue
        }
    }

    // MARK: - Aide interne de sécurité

    /// Efface les clés de session en RAM et verrouille le canal (principe : échouer en sécurité).
    private func verrouillerEnSecurite(raison: String) {
        cleSessionIPhoneVersMac = nil
        cleSessionMacVersIPhone = nil
        etat = .verrouille(raison: raison)
    }
}
#endif
