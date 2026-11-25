#if canImport(CryptoKit)
import Foundation
import CryptoKit

// MARK: - Modèles et erreurs d'appairage (MAC-2, étiquette `crypto` -> relecture Aïda obligatoire)

/// État du cycle d'appairage entre la centrale Mac et le capteur iPhone (`MAC-2`).
///
/// Principe de sécurité (`CLAUDE.md` §6) : « Échouer en sécurité ».
/// Tant que l'état n'est pas `.appaire`, le pair n'est pas considéré comme de confiance (`E2`).
public enum EtatAppairageMac: Equatable, Sendable {
    /// Aucun appairage en cours ; les clés sont absentes ou ont été purgées.
    case nonAppaire
    /// Le QR code est généré et affiché sur le Mac, en attente du scan et de la demande de l'iPhone.
    case qrCodeAffiche(chargeQR: ChargeUtileQRAppairage, donneesQR: Data)
    /// La clé de l'iPhone et sa preuve de possession ont été vérifiées ; l'utilisateur doit confirmer
    /// visuellement que le code court et l'empreinte affichés sur les deux écrans sont identiques (`S4`, `H4`).
    case attenteConfirmationEmpreinte(codeCourt: String, empreinteMutuelleHex: String)
    /// L'utilisateur a confirmé l'empreinte : la clé publique d'identité de l'iPhone est enregistrée en RAM.
    case appaire(empreinteIPhoneHex: String)
    /// L'appairage a été refusé ou a échoué en sécurité (mauvaise empreinte, signature invalide, QR malformé).
    case rejete(raison: String)
}

/// Erreurs de validation et de cryptographie lors de l'appairage par QR code (`MAC-2`).
///
/// Menaces STRIDE couvertes :
/// - `S1` : Homme du milieu / faux Mac lors de l'appairage (`empreinteMacNonConcordante`, `signaturePreuveInvalide`).
/// - `S4` : Substitution de QR code (`nonceNonConcordant`, `confirmationRefuseeParUtilisateur`).
/// - `T4` : Contenu de QR code malformé, vide ou surdimensionné (`qrCodeVide`, `qrCodeTropGrand`, `formatJSONInvalide`, etc.).
/// - `E2` : Tentative d'action par un pair non appairé (`etatAppairageInvalide`).
public enum ErreurAppairageCrypto: Error, Equatable, Sendable {
    /// Le contenu brut du QR code est vide (0 octet).
    case qrCodeVide
    /// Le contenu brut du QR code dépasse le plafond de sécurité de 1 024 octets (`T4`).
    case qrCodeTropGrand(Int)
    /// Le JSON du QR code ou du message d'appairage est malformé (`T4`).
    case formatJSONInvalide
    /// Le libellé de version du QR code n'est pas `"antitracker-qr-v1"` (`T4`).
    case versionProtocoleInconnue(String)
    /// Le nom du service Bonjour dans le QR code est vide ou dépasse 63 caractères (`T4`).
    case nomServiceInvalide
    /// Le numéro de port TCP dans le QR code vaut 0 (`T4`).
    case portInvalide
    /// L'empreinte SHA-256 de la clé publique ne mesure pas exactement 32 octets (`T4`, `S1`).
    case tailleEmpreinteInvalide(Int)
    /// Le nonce d'appairage ne mesure pas exactement 16 octets (`T4`).
    case tailleNonceInvalide(Int)
    /// La représentation brute de la clé publique P-256 ne mesure pas 64 octets ou n'est pas un point valide sur P-256.
    case clePubliqueP256Invalide
    /// L'empreinte SHA-256 de la clé publique reçue du Mac ne correspond pas à celle scannée dans le QR code (`S1`).
    case empreinteMacNonConcordante
    /// Le nonce retourné dans le message réseau ne correspond pas au nonce du QR code actif (`S1`, `S4`).
    case nonceNonConcordant
    /// La signature ECDSA P-256 de preuve de possession de la clé privée est invalide (`S1`, `S2`).
    case signaturePreuveInvalide
    /// L'opération demandée ne correspond pas à l'étape courante de la machine à états d'appairage (`E2`).
    case etatAppairageInvalide
    /// L'utilisateur a explicitement rejeté la correspondance de l'empreinte / du code court (`S4`, `E2`).
    case confirmationRefuseeParUtilisateur
}

/// Charge utile encodée dans le QR code affiché par la centrale Mac (`MAC-2`, frontière `F2`).
///
/// Conforme à `docs/securite/CHOIX_CRYPTO.md` (§2 et §3.2) et `docs/architecture/schema-architecture.md` (§3) :
/// contient l'empreinte SHA-256 de la clé publique d'identité du Mac, les paramètres de connexion locale
/// et un nonce aléatoire de 16 octets.
public struct ChargeUtileQRAppairage: Codable, Equatable, Sendable {
    /// Identifiant de version fixe du format de QR code pour rejeter tout QR code étranger (`T4`).
    public static let versionAttendue = "antitracker-qr-v1"
    /// Taille maximale autorisée pour les données brutes d'un QR code (1 024 octets, contre `T4`).
    public static let tailleMaxOctetsQR = 1_024
    /// Taille exacte d'une empreinte SHA-256 (32 octets / 256 bits).
    public static let tailleEmpreinteSHA256 = 32
    /// Taille exacte du nonce d'appairage (16 octets / 128 bits).
    public static let tailleNonceAppairage = 16
    /// Longueur maximale d'un nom de service Bonjour (RFC 6763).
    public static let longueurMaxNomService = 63

    /// Version du protocole de QR code (`"antitracker-qr-v1"`).
    public let version: String
    /// Nom du service Bonjour annoncé par la centrale Mac.
    public let nomService: String
    /// Port TCP d'écoute du `NWListener` sur le Mac.
    public let port: UInt16
    /// Empreinte `SHA-256` (32 octets) de la représentation brute (`rawRepresentation`) de la clé publique P-256 du Mac.
    public let empreinteClePubliqueMac: Data
    /// Nonce aléatoire (16 octets) généré par CryptoKit pour lier l'appairage à ce QR code unique.
    public let nonceAppairage: Data

    /// Initialise une charge utile de QR code d'appairage.
    public init(
        version: String = Self.versionAttendue,
        nomService: String,
        port: UInt16,
        empreinteClePubliqueMac: Data,
        nonceAppairage: Data
    ) {
        self.version = version
        self.nomService = nomService
        self.port = port
        self.empreinteClePubliqueMac = empreinteClePubliqueMac
        self.nonceAppairage = nonceAppairage
    }

    /// Valide strictement tous les champs de la charge utile après décodage (contre `T4`).
    ///
    /// - Throws: `ErreurAppairageCrypto` si un champ ne respecte pas les bornes de sécurité.
    public func validerFormat() throws {
        guard version == Self.versionAttendue else {
            throw ErreurAppairageCrypto.versionProtocoleInconnue(version)
        }
        let nomNettoye = nomService.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nomNettoye.isEmpty, nomNettoye.utf8.count <= Self.longueurMaxNomService else {
            throw ErreurAppairageCrypto.nomServiceInvalide
        }
        guard port > 0 else {
            throw ErreurAppairageCrypto.portInvalide
        }
        guard empreinteClePubliqueMac.count == Self.tailleEmpreinteSHA256 else {
            throw ErreurAppairageCrypto.tailleEmpreinteInvalide(empreinteClePubliqueMac.count)
        }
        guard nonceAppairage.count == Self.tailleNonceAppairage else {
            throw ErreurAppairageCrypto.tailleNonceInvalide(nonceAppairage.count)
        }
    }

    /// Encode la charge utile en JSON après avoir vérifié sa validité et sa taille maximale (`<= 1 024` octets).
    ///
    /// - Returns: Les octets JSON prêts à être transformés en image QR code.
    /// - Throws: `ErreurAppairageCrypto` en cas d'erreur de validation ou de dépassement de taille.
    public func encoderPourQRCode() throws -> Data {
        try validerFormat()
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        let donnees: Data
        do {
            donnees = try encodeur.encode(self)
        } catch {
            throw ErreurAppairageCrypto.formatJSONInvalide
        }
        guard donnees.count <= Self.tailleMaxOctetsQR else {
            throw ErreurAppairageCrypto.qrCodeTropGrand(donnees.count)
        }
        return donnees
    }

    /// Décode et valide une `ChargeUtileQRAppairage` à partir d'octets bruts lus par le scanner de QR code (frontière `F2`).
    ///
    /// Aucun `!`, `try!` ni `fatalError` n'est utilisé (`CLAUDE.md` §7).
    /// La taille maximale (`1 024` octets) est vérifiée **avant** d'invoquer `JSONDecoder` (`T4`, `D3`).
    ///
    /// - Parameter donneesBrutes: Les octets extraits du QR code.
    /// - Returns: La `ChargeUtileQRAppairage` validée.
    /// - Throws: `ErreurAppairageCrypto` si les données sont vides, trop longues ou invalides.
    public static func decoderDepuisQRCode(_ donneesBrutes: Data) throws -> ChargeUtileQRAppairage {
        guard !donneesBrutes.isEmpty else {
            throw ErreurAppairageCrypto.qrCodeVide
        }
        guard donneesBrutes.count <= tailleMaxOctetsQR else {
            throw ErreurAppairageCrypto.qrCodeTropGrand(donneesBrutes.count)
        }

        let decodeur = JSONDecoder()
        let charge: ChargeUtileQRAppairage
        do {
            charge = try decodeur.decode(ChargeUtileQRAppairage.self, from: donneesBrutes)
        } catch {
            throw ErreurAppairageCrypto.formatJSONInvalide
        }

        try charge.validerFormat()
        return charge
    }
}

/// Message réseau envoyé par l'iPhone au Mac après lecture du QR code pour demander l'appairage (`MAC-2`).
///
/// L'iPhone fournit sa clé publique d'identité P-256 (64 octets bruts) et une signature ECDSA P-256
/// prouvant qu'il détient la clé privée correspondante (logée dans sa Secure Enclave) sur :
/// `"antitracker-preuve-iphone-v1" || nonceAppairage || empreinteClePubliqueMac || clePubliqueIPhone`.
public struct DemandeAppairageIPhone: Codable, Equatable, Sendable {
    /// Taille exacte de la représentation brute (`rawRepresentation`) d'une clé publique P-256 (64 octets : X || Y).
    public static let tailleClePubliqueP256Brute = 64

    /// Représentation brute (`rawRepresentation`, 64 octets) de la clé publique P-256 d'identité de l'iPhone.
    public let clePubliqueIPhoneBrute: Data
    /// Nonce d'appairage (16 octets) lu dans le QR code du Mac.
    public let nonceAppairage: Data
    /// Signature ECDSA P-256 (`rawRepresentation`) produite par la clé privée d'identité de l'iPhone.
    public let signaturePreuveIPhone: Data

    public init(
        clePubliqueIPhoneBrute: Data,
        nonceAppairage: Data,
        signaturePreuveIPhone: Data
    ) {
        self.clePubliqueIPhoneBrute = clePubliqueIPhoneBrute
        self.nonceAppairage = nonceAppairage
        self.signaturePreuveIPhone = signaturePreuveIPhone
    }
}

/// Réponse réseau du Mac envoyée à l'iPhone lors de l'appairage (`MAC-2`).
///
/// Le Mac fournit sa clé publique P-256 complète (dont l'iPhone vérifie que le SHA-256 correspond au QR code, `S1`)
/// et une signature ECDSA P-256 prouvant qu'il possède la clé privée correspondante sur :
/// `"antitracker-preuve-mac-v1" || nonceAppairage || clePubliqueIPhone || clePubliqueMac`.
public struct ReponseAppairageMac: Codable, Equatable, Sendable {
    /// Représentation brute (`rawRepresentation`, 64 octets) de la clé publique P-256 d'identité du Mac.
    public let clePubliqueMacBrute: Data
    /// Nonce d'appairage (16 octets) issu du QR code.
    public let nonceAppairage: Data
    /// Signature ECDSA P-256 (`rawRepresentation`) produite par la clé privée d'identité du Mac.
    public let signaturePreuveMac: Data

    public init(
        clePubliqueMacBrute: Data,
        nonceAppairage: Data,
        signaturePreuveMac: Data
    ) {
        self.clePubliqueMacBrute = clePubliqueMacBrute
        self.nonceAppairage = nonceAppairage
        self.signaturePreuveMac = signaturePreuveMac
    }
}

// MARK: - Protocole du service d'appairage cryptographique

/// Contrat abstrait du service d'appairage cryptographique (`CLAUDE.md` §7 : chaque service est derrière un `protocol`).
public protocol ServiceAppairageCryptoProtocol: AnyObject {
    /// État courant de la machine à états d'appairage.
    var etat: EtatAppairageMac { get }
    /// Indique si un capteur iPhone est actuellement appairé et confirmé par l'utilisateur.
    var estAppaire: Bool { get }
    /// Clé publique P-256 d'identité de l'iPhone appairé (uniquement disponible lorsque `etat` est `.appaire`).
    var clePubliqueIPhoneAppaire: P256.Signing.PublicKey? { get }

    /// Génère une nouvelle paire de clés d'identité P-256 en RAM et prépare la charge utile du QR code.
    ///
    /// - Parameters:
    ///   - nomService: Nom du service Bonjour de la centrale.
    ///   - port: Port TCP d'écoute (> 0).
    /// - Returns: La charge utile validée et ses octets JSON prêts pour le QR code.
    /// - Throws: `ErreurAppairageCrypto` si les paramètres sont invalides.
    @discardableResult
    func demarrerNouvelAppairage(nomService: String, port: UInt16) throws -> (ChargeUtileQRAppairage, Data)

    /// Traite une demande d'appairage reçue d'un iPhone, vérifie le nonce et la signature ECDSA P-256,
    /// calcule le code court de vérification mutuelle et prépare la réponse signée du Mac.
    ///
    /// - Parameter demande: La demande d'appairage envoyée par l'iPhone.
    /// - Returns: La réponse signée du Mac (`ReponseAppairageMac`) à renvoyer à l'iPhone.
    /// - Throws: `ErreurAppairageCrypto` si le nonce, la clé ou la signature est invalide (bascule en `.rejete`).
    func traiterDemandeAppairageIPhone(_ demande: DemandeAppairageIPhone) throws -> ReponseAppairageMac

    /// Confirme manuellement (action utilisateur sur le Mac) que le code court affiché correspond à celui de l'iPhone.
    ///
    /// - Throws: `ErreurAppairageCrypto.etatAppairageInvalide` si aucune confirmation n'était en attente.
    func confirmerEmpreinteParUtilisateur() throws

    /// Refuse manuellement l'appairage si le code court affiché diffère de celui de l'iPhone (`S4`, `E2`).
    func refuserEmpreinteParUtilisateur()

    /// Efface immédiatement de la mémoire vive (RAM) la clé privée du Mac, la clé publique de l'iPhone et le nonce (`MAC-7`, `I4`).
    func purgerClesEnMemoire()
}

// MARK: - Implémentation CryptoKit du service d'appairage (MAC-2)

/// Implémentation cryptographique de l'appairage par QR code avec vérification d'empreinte (`MAC-2`).
///
/// Conforme à `CLAUDE.md` (§6 et §7) et `docs/securite/CHOIX_CRYPTO.md` (§3.1 et §3.2) :
/// - Utilise **exclusivement CryptoKit** (`P256.Signing`, `SHA256`, `SymmetricKey`).
/// - Isolé dans le dossier `CentraleMac/Crypto/` pour la relecture obligatoire d'Aïda.
/// - Toutes les clés résident uniquement en mémoire vive (RAM) et sont détruites lors de la purge (`ARCH-7`, `I4`).
public final class ServiceAppairageCrypto: ServiceAppairageCryptoProtocol {
    /// Libellé de séparation de domaine pour la signature de preuve de possession côté iPhone.
    public static let contextePreuveIPhone = "antitracker-preuve-iphone-v1"
    /// Libellé de séparation de domaine pour la signature de preuve de possession côté Mac.
    public static let contextePreuveMac = "antitracker-preuve-mac-v1"
    /// Libellé de séparation de domaine pour le calcul de l'empreinte mutuelle et du code court à 6 chiffres.
    public static let contexteEmpreinteMutuelle = "antitracker-empreinte-v1"

    /// État courant de l'appairage.
    public private(set) var etat: EtatAppairageMac = .nonAppaire

    /// Clé privée d'identité P-256 de la centrale Mac (conservée en RAM uniquement pendant la séance).
    private var clePriveeIdentiteMac: P256.Signing.PrivateKey?
    /// Charge utile du QR code actif en attente d'appairage.
    private var chargeQRActive: ChargeUtileQRAppairage?
    /// Clé publique de l'iPhone en attente de confirmation visuelle du code court par l'utilisateur.
    private var clePubliqueIPhoneEnAttente: P256.Signing.PublicKey?
    /// Clé publique de l'iPhone validée après confirmation de l'empreinte par l'utilisateur.
    public private(set) var clePubliqueIPhoneAppaire: P256.Signing.PublicKey?

    public var estAppaire: Bool {
        if case .appaire = etat, clePubliqueIPhoneAppaire != nil {
            return true
        }
        return false
    }

    public init() {}

    // MARK: - Étape 1 : Génération de la clé d'identité Mac en RAM et du QR code

    @discardableResult
    public func demarrerNouvelAppairage(
        nomService: String,
        port: UInt16
    ) throws -> (ChargeUtileQRAppairage, Data) {
        // Nettoyage préalable de tout état ou clé antérieure en mémoire.
        purgerClesEnMemoire()

        // 1. Génération d'une nouvelle paire de clés ECDSA P-256 en mémoire vive (CryptoKit).
        let nouvelleClePriveeMac = P256.Signing.PrivateKey()
        let clePubliqueMacBrute = nouvelleClePriveeMac.publicKey.rawRepresentation

        // 2. Calcul de l'empreinte SHA-256 (32 octets) de la clé publique du Mac.
        let empreinteMac = Self.calculerEmpreinteSHA256(donnees: clePubliqueMacBrute)

        // 3. Génération d'un nonce aléatoire cryptographique de 16 octets (128 bits) via CryptoKit.
        let nonce = Self.genererNonce16Octets()

        // 4. Construction et validation stricte de la charge utile du QR code.
        let chargeQR = ChargeUtileQRAppairage(
            nomService: nomService,
            port: port,
            empreinteClePubliqueMac: empreinteMac,
            nonceAppairage: nonce
        )
        let donneesQR = try chargeQR.encoderPourQRCode()

        // 5. Enregistrement en RAM et passage à l'état `.qrCodeAffiche`.
        self.clePriveeIdentiteMac = nouvelleClePriveeMac
        self.chargeQRActive = chargeQR
        self.etat = .qrCodeAffiche(chargeQR: chargeQR, donneesQR: donneesQR)

        return (chargeQR, donneesQR)
    }

    // MARK: - Étape 2 : Réception et vérification de la demande d'appairage de l'iPhone

    public func traiterDemandeAppairageIPhone(
        _ demande: DemandeAppairageIPhone
    ) throws -> ReponseAppairageMac {
        // Vérifie que la centrale attend bien un appairage avec une clé et un QR code actifs.
        guard case .qrCodeAffiche = etat,
              let clePriveeMac = clePriveeIdentiteMac,
              let chargeQR = chargeQRActive else {
            throw ErreurAppairageCrypto.etatAppairageInvalide
        }

        // 1. Vérification du nonce (doit correspondre exactement aux 16 octets du QR code actif, contre S1 / S4).
        guard demande.nonceAppairage.count == ChargeUtileQRAppairage.tailleNonceAppairage,
              comparerEnTempsConstant(demande.nonceAppairage, chargeQR.nonceAppairage) else {
            echouerEnSecurite(raison: "Nonce d'appairage invalide ou expiré.")
            throw ErreurAppairageCrypto.nonceNonConcordant
        }

        // 2. Reconstruction et validation de la clé publique P-256 de l'iPhone (64 octets bruts).
        guard demande.clePubliqueIPhoneBrute.count == DemandeAppairageIPhone.tailleClePubliqueP256Brute else {
            echouerEnSecurite(raison: "Taille de clé publique iPhone invalide.")
            throw ErreurAppairageCrypto.clePubliqueP256Invalide
        }
        let clePubliqueIPhone: P256.Signing.PublicKey
        do {
            clePubliqueIPhone = try P256.Signing.PublicKey(rawRepresentation: demande.clePubliqueIPhoneBrute)
        } catch {
            echouerEnSecurite(raison: "Clé publique P-256 iPhone malformée.")
            throw ErreurAppairageCrypto.clePubliqueP256Invalide
        }

        // 3. Vérification de la signature ECDSA P-256 de preuve de possession de l'iPhone (contre S1 / S2).
        let signatureIPhone: P256.Signing.ECDSASignature
        do {
            signatureIPhone = try P256.Signing.ECDSASignature(rawRepresentation: demande.signaturePreuveIPhone)
        } catch {
            echouerEnSecurite(raison: "Format de signature ECDSA iPhone invalide.")
            throw ErreurAppairageCrypto.signaturePreuveInvalide
        }

        let donneesSigneesParIPhone = Self.construireDonneesPreuveIPhone(
            nonceAppairage: chargeQR.nonceAppairage,
            empreinteClePubliqueMac: chargeQR.empreinteClePubliqueMac,
            clePubliqueIPhoneBrute: clePubliqueIPhone.rawRepresentation
        )

        guard clePubliqueIPhone.isValidSignature(signatureIPhone, for: donneesSigneesParIPhone) else {
            echouerEnSecurite(raison: "La signature de preuve de l'iPhone est invalide.")
            throw ErreurAppairageCrypto.signaturePreuveInvalide
        }

        // 4. Construction de la réponse signée par la clé privée du Mac (prouve à l'iPhone que le Mac détient la clé du QR code).
        let clePubliqueMacBrute = clePriveeMac.publicKey.rawRepresentation
        let donneesASignerParMac = Self.construireDonneesPreuveMac(
            nonceAppairage: chargeQR.nonceAppairage,
            clePubliqueIPhoneBrute: clePubliqueIPhone.rawRepresentation,
            clePubliqueMacBrute: clePubliqueMacBrute
        )

        let signatureMac: P256.Signing.ECDSASignature
        do {
            signatureMac = try clePriveeMac.signature(for: donneesASignerParMac)
        } catch {
            echouerEnSecurite(raison: "Échec interne de signature côté Mac.")
            throw ErreurAppairageCrypto.signaturePreuveInvalide
        }

        // 5. Calcul du code court à 6 chiffres et de l'empreinte hexadécimale mutuelle à comparer par l'utilisateur (S4, H4).
        let (codeCourt, empreinteHex) = Self.calculerCodeCourtEtEmpreinteMutuelle(
            clePubliqueMacBrute: clePubliqueMacBrute,
            clePubliqueIPhoneBrute: clePubliqueIPhone.rawRepresentation,
            nonceAppairage: chargeQR.nonceAppairage
        )

        // 6. Mise en attente de la confirmation explicite de l'utilisateur (aucune alerte n'est acceptée à ce stade).
        self.clePubliqueIPhoneEnAttente = clePubliqueIPhone
        self.etat = .attenteConfirmationEmpreinte(
            codeCourt: codeCourt,
            empreinteMutuelleHex: empreinteHex
        )

        return ReponseAppairageMac(
            clePubliqueMacBrute: clePubliqueMacBrute,
            nonceAppairage: chargeQR.nonceAppairage,
            signaturePreuveMac: signatureMac.rawRepresentation
        )
    }

    // MARK: - Étape 3 : Confirmation ou refus de l'empreinte par l'utilisateur (S4, E2, H4)

    public func confirmerEmpreinteParUtilisateur() throws {
        guard case .attenteConfirmationEmpreinte = etat,
              let cleValidee = clePubliqueIPhoneEnAttente else {
            throw ErreurAppairageCrypto.etatAppairageInvalide
        }

        let empreinteIPhone = Self.calculerEmpreinteSHA256(donnees: cleValidee.rawRepresentation)
        let empreinteCourteHex = empreinteIPhone.prefix(4).map { String(format: "%02X", $0) }.joined()

        self.clePubliqueIPhoneAppaire = cleValidee
        self.clePubliqueIPhoneEnAttente = nil
        self.chargeQRActive = nil
        self.etat = .appaire(empreinteIPhoneHex: empreinteCourteHex)
    }

    public func refuserEmpreinteParUtilisateur() {
        echouerEnSecurite(raison: "Empreinte refusée par l'utilisateur.")
    }

    // MARK: - Étape 4 : Purge en mémoire vive (MAC-7, I4)

    public func purgerClesEnMemoire() {
        clePriveeIdentiteMac = nil
        chargeQRActive = nil
        clePubliqueIPhoneEnAttente = nil
        clePubliqueIPhoneAppaire = nil
        etat = .nonAppaire
    }

    // MARK: - Fonctions cryptographiques pures et utilitaires côté iPhone / Mac

    /// Calcule le condensat `SHA-256` (32 octets) d'un bloc de données via CryptoKit.
    public static func calculerEmpreinteSHA256(donnees: Data) -> Data {
        Data(SHA256.hash(data: donnees))
    }

    /// Génère un nonce aléatoire cryptographique de 16 octets via `SymmetricKey` (CryptoKit).
    public static func genererNonce16Octets() -> Data {
        let cleAleatoire = SymmetricKey(size: .bits128)
        return cleAleatoire.withUnsafeBytes { Data($0) }
    }

    /// Construit le bloc de données canonique signé par l'iPhone pour prouver la possession de sa clé privée.
    ///
    /// Format : `"antitracker-preuve-iphone-v1" || nonce (16 o) || empreinteMac (32 o) || clePubliqueIPhone (64 o)`.
    public static func construireDonneesPreuveIPhone(
        nonceAppairage: Data,
        empreinteClePubliqueMac: Data,
        clePubliqueIPhoneBrute: Data
    ) -> Data {
        var tampon = Data(contextePreuveIPhone.utf8)
        tampon.append(nonceAppairage)
        tampon.append(empreinteClePubliqueMac)
        tampon.append(clePubliqueIPhoneBrute)
        return tampon
    }

    /// Construit le bloc de données canonique signé par le Mac pour prouver la possession de sa clé privée.
    ///
    /// Format : `"antitracker-preuve-mac-v1" || nonce (16 o) || clePubliqueIPhone (64 o) || clePubliqueMac (64 o)`.
    public static func construireDonneesPreuveMac(
        nonceAppairage: Data,
        clePubliqueIPhoneBrute: Data,
        clePubliqueMacBrute: Data
    ) -> Data {
        var tampon = Data(contextePreuveMac.utf8)
        tampon.append(nonceAppairage)
        tampon.append(clePubliqueIPhoneBrute)
        tampon.append(clePubliqueMacBrute)
        return tampon
    }

    /// Vérifie côté iPhone la réponse d'appairage envoyée par le Mac (contre `S1` : homme du milieu).
    ///
    /// Vérifie :
    /// 1. Que le nonce correspond au QR code scanné.
    /// 2. Que `SHA-256(clePubliqueMacBrute)` est **strictement égal** à `empreinteClePubliqueMac` lue dans le QR code (`S1`).
    /// 3. Que la signature ECDSA P-256 du Mac est valide pour cette clé publique et la clé de l'iPhone.
    ///
    /// - Parameters:
    ///   - reponse: La réponse reçue du Mac sur le réseau local.
    ///   - chargeQR: La charge utile extraite du QR code scanné.
    ///   - clePubliqueIPhoneBrute: La clé publique brute (64 octets) envoyée par l'iPhone.
    /// - Returns: La clé publique P-256 authentifiée du Mac, ainsi que le code court et l'empreinte mutuelle à afficher sur l'iPhone.
    /// - Throws: `ErreurAppairageCrypto` si l'empreinte diffère du QR code (`S1`) ou si la signature est invalide.
    public static func verifierReponseMacCoteIPhone(
        reponse: ReponseAppairageMac,
        chargeQR: ChargeUtileQRAppairage,
        clePubliqueIPhoneBrute: Data
    ) throws -> (clePubliqueMac: P256.Signing.PublicKey, codeCourt: String, empreinteMutuelleHex: String) {
        // 1. Vérification du nonce en temps constant.
        guard reponse.nonceAppairage.count == ChargeUtileQRAppairage.tailleNonceAppairage,
              comparerEnTempsConstantStatique(reponse.nonceAppairage, chargeQR.nonceAppairage) else {
            throw ErreurAppairageCrypto.nonceNonConcordant
        }

        // 2. Vérification de la taille et de la validité de la clé publique P-256 du Mac.
        guard reponse.clePubliqueMacBrute.count == DemandeAppairageIPhone.tailleClePubliqueP256Brute else {
            throw ErreurAppairageCrypto.clePubliqueP256Invalide
        }
        let clePubliqueMac: P256.Signing.PublicKey
        do {
            clePubliqueMac = try P256.Signing.PublicKey(rawRepresentation: reponse.clePubliqueMacBrute)
        } catch {
            throw ErreurAppairageCrypto.clePubliqueP256Invalide
        }

        // 3. Vérification fondamentale contre S1 (Homme du milieu) :
        //    SHA-256(clé publique reçue sur le réseau) DOIT être égal à l'empreinte lue dans le QR code.
        let empreinteRecalculee = calculerEmpreinteSHA256(donnees: clePubliqueMac.rawRepresentation)
        guard comparerEnTempsConstantStatique(empreinteRecalculee, chargeQR.empreinteClePubliqueMac) else {
            throw ErreurAppairageCrypto.empreinteMacNonConcordante
        }

        // 4. Vérification de la signature ECDSA P-256 du Mac.
        let signatureMac: P256.Signing.ECDSASignature
        do {
            signatureMac = try P256.Signing.ECDSASignature(rawRepresentation: reponse.signaturePreuveMac)
        } catch {
            throw ErreurAppairageCrypto.signaturePreuveInvalide
        }

        let donneesSignees = construireDonneesPreuveMac(
            nonceAppairage: chargeQR.nonceAppairage,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
            clePubliqueMacBrute: clePubliqueMac.rawRepresentation
        )
        guard clePubliqueMac.isValidSignature(signatureMac, for: donneesSignees) else {
            throw ErreurAppairageCrypto.signaturePreuveInvalide
        }

        // 5. Calcul du code court et de l'empreinte mutuelle à afficher sur l'écran de l'iPhone.
        let (codeCourt, empreinteHex) = calculerCodeCourtEtEmpreinteMutuelle(
            clePubliqueMacBrute: clePubliqueMac.rawRepresentation,
            clePubliqueIPhoneBrute: clePubliqueIPhoneBrute,
            nonceAppairage: chargeQR.nonceAppairage
        )

        return (clePubliqueMac, codeCourt, empreinteHex)
    }

    /// Calcule de façon déterministe le code court à 6 chiffres (ex. `"482 910"`) et l'empreinte hexadécimale
    /// courte (ex. `"A1B2-C3D4"`) liant la clé du Mac, la clé de l'iPhone et le nonce d'appairage (`S4`, `E2`).
    ///
    /// Formule : `H = SHA-256("antitracker-empreinte-v1" || clePubliqueMac || clePubliqueIPhone || nonce)`.
    public static func calculerCodeCourtEtEmpreinteMutuelle(
        clePubliqueMacBrute: Data,
        clePubliqueIPhoneBrute: Data,
        nonceAppairage: Data
    ) -> (codeCourt: String, empreinteHex: String) {
        var tampon = Data(contexteEmpreinteMutuelle.utf8)
        tampon.append(clePubliqueMacBrute)
        tampon.append(clePubliqueIPhoneBrute)
        tampon.append(nonceAppairage)

        let condensat = [UInt8](SHA256.hash(data: tampon))

        // Extraction des 4 premiers octets en un entier 32 bits non signé Big-Endian pour produire 6 chiffres décimaux.
        let valeur32Bits: UInt32 =
            (UInt32(condensat[0]) << 24) |
            (UInt32(condensat[1]) << 16) |
            (UInt32(condensat[2]) << 8)  |
            UInt32(condensat[3])
        let sixChiffres = valeur32Bits % 1_000_000
        let partieHaute = sixChiffres / 1_000
        let partieBasse = sixChiffres % 1_000
        let codeCourt = String(format: "%03d %03d", partieHaute, partieBasse)

        // Extraction des octets 4..7 pour une empreinte hexadécimale lisible de 8 caractères (XXXX-XXXX).
        let blocHex1 = String(format: "%02X%02X", condensat[4], condensat[5])
        let blocHex2 = String(format: "%02X%02X", condensat[6], condensat[7])
        let empreinteHex = "\(blocHex1)-\(blocHex2)"

        return (codeCourt, empreinteHex)
    }

    // MARK: - Aides internes de sécurité

    /// Bascule l'état en `.rejete` et efface immédiatement les clés en attente (principe : échouer en sécurité).
    private func echouerEnSecurite(raison: String) {
        clePriveeIdentiteMac = nil
        chargeQRActive = nil
        clePubliqueIPhoneEnAttente = nil
        clePubliqueIPhoneAppaire = nil
        etat = .rejete(raison: raison)
    }

    /// Compare deux blocs `Data` en temps constant pour éviter toute fuite par canal auxiliaire temporel.
    private func comparerEnTempsConstant(_ a: Data, _ b: Data) -> Bool {
        Self.comparerEnTempsConstantStatique(a, b)
    }

    /// Compare deux blocs `Data` de même taille en temps constant (XOR bit à bit sans court-circuit).
    private static func comparerEnTempsConstantStatique(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (octetA, octetB) in zip(a, b) {
            difference |= (octetA ^ octetB)
        }
        return difference == 0
    }
}
#endif
