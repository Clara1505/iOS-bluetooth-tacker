import Foundation

// MARK: - Modèles et erreurs de limitation de débit et de rejet rapide (MAC-6)

/// Décision du contrôleur de rejet rapide et de limitation de débit (`MAC-6`).
///
/// Menaces STRIDE couvertes (`docs/securite/STRIDE.md`) :
/// - `D2` : Flood de messages vers la centrale (rejet en `O(1)` avant toute opération CryptoKit coûteuse).
/// - `E2` : Envoi de messages par un client alors qu'aucun pair n'est appairé ou que le canal chiffré est fermé.
/// - `D3` : Rafale de trames non authentifiées ou corrompues entraînant la coupure immédiate du client.
public enum DecisionFiltrageRapide: Equatable, Sendable {
    /// Le message respecte les prérequis d'état, de taille et de débit : il peut passer à CryptoKit.
    case autorise
    /// Rejet immédiat : aucun iPhone n'est appairé et confirmé (`MAC-2`, menace `E2`).
    case rejetePairNonAppaire
    /// Rejet immédiat : le canal chiffré (`MAC-3`) n'est pas ouvert (`E2`, `D2`).
    case rejeteCanalNonOuvert
    /// Rejet immédiat : la taille du bloc est inférieure au minimum d'un bloc AES-GCM (29 octets) ou dépasse 64 Ko (`D2`, `D3`).
    case rejeteTailleInvalide(Int)
    /// Rejet immédiat : le client dépasse le plafond de messages autorisés dans la fenêtre de temps (`D2`).
    case rejeteDebitDepasse(messagesDansFenetre: Int, plafond: Int)
    /// Rejet immédiat : le client a cumulé trop d'échecs d'authentification consécutifs et est temporairement bloqué (`D2`, `E2`).
    case rejeteClientVerrouilleApresEchecs(echecsConsecutifs: Int)
}

// MARK: - Protocole du service de limitation de débit et rejet rapide (`CLAUDE.md` §7)

/// Contrat abstrait du contrôleur de rejet rapide et de limitation de débit côté centrale Mac (`MAC-6`).
public protocol ServiceLimitationDebitProtocol: AnyObject {
    /// Nombre maximal de messages autorisés par fenêtre glissante (`10` messages par seconde par défaut).
    var nombreMaxMessagesParFenetre: Int { get }
    /// Durée de la fenêtre glissante en secondes (`1.0` seconde par défaut).
    var dureeFenetreSecondes: TimeInterval { get }
    /// Seuil d'échecs d'authentification consécutifs déclenchant le blocage immédiat de la session (`3` par défaut).
    var seuilEchecsAuthentificationConsecutifs: Int { get }
    /// Nombre actuel d'échecs d'authentification consécutifs relevés.
    var echecsAuthentificationConsecutifs: Int { get }
    /// Compteur total de messages rejetés par le filtre rapide ou le limiteur de débit depuis le début de la séance.
    var nombreRejetsRapides: Int { get }

    /// Évalue en `O(1)` (avant tout appel à CryptoKit) si un message entrant peut être traité ou doit être rejeté immédiatement (`MAC-6`).
    ///
    /// - Parameters:
    ///   - tailleOctets: Taille en octets de la trame entrante.
    ///   - estPairAppaire: Indique si un iPhone est actuellement appairé et confirmé (`MAC-2`).
    ///   - estCanalOuvert: Indique si le canal chiffré `AES-256-GCM` est ouvert (`MAC-3`).
    ///   - dateReception: Horodatage de réception (`Date()` par défaut ; injectable pour les tests unitaires).
    /// - Returns: `.autorise` si le message peut être déchiffré et vérifié, ou la raison exacte du rejet rapide.
    func evaluerMessageEntrant(
        tailleOctets: Int,
        estPairAppaire: Bool,
        estCanalOuvert: Bool,
        dateReception: Date
    ) -> DecisionFiltrageRapide

    /// Signale au contrôleur qu'un message a échoué à la vérification cryptographique (`AES-GCM` ou signature `ECDSA`),
    /// ce qui incrémente le compteur d'échecs consécutifs vers le verrouillage rapide (`D2`, `E2`).
    func signalerEchecAuthentification()

    /// Signale au contrôleur qu'un message a été authentifié avec succès, ce qui remet à zéro les échecs consécutifs.
    func signalerSuccesAuthentification()

    /// Réinitialise tous les compteurs et la fenêtre glissante en mémoire vive (`MAC-7`, `I4`).
    func reinitialiserLimiteur()
}

// MARK: - Implémentation du limiteur de débit et rejet pré-cryptographique (MAC-6)

/// Implémentation du contrôleur de rejet rapide pré-cryptographique et de limitation de débit à fenêtre glissante (`MAC-6`).
///
/// Conforme à `docs/securite/STRIDE.md` (menaces `D2`, `D3`, `E2`) :
/// 1. **Court-circuit avant CryptoKit (*Fast-Fail*)** : si l'iPhone n'est pas appairé (`E2`), si le canal chiffré est fermé,
///    si le client a dépassé le seuil d'échecs d'authentification, ou si la taille du paquet ne correspond pas à un bloc
///    `AES-256-GCM` valide (`29 <= taille <= 65 536` octets), le message est rejeté instantanément sans consommer de CPU
///    sur `AES.GCM.open` ni sur la vérification de signature `P-256 ECDSA`.
/// 2. **Fenêtre glissante (*Sliding Window Rate Limiter*)** : conserve uniquement les horodatages de la dernière seconde
///    et rejette tout paquet au-delà de `nombreMaxMessagesParFenetre` (10 msg/s par défaut), garantissant que la centrale
///    reste fluide même sous un flood massif (`RT-4`, test STRIDE `D2`).
/// 3. **Blocage après échecs d'authentification répétés** : au bout de `3` messages non authentifiés consécutifs,
///    tous les paquets suivants sont rejetés en `O(1)` jusqu'à la réinitialisation ou un nouvel appairage.
public final class ServiceLimitationDebit: ServiceLimitationDebitProtocol {
    /// Taille minimale d'un bloc combiné AES-256-GCM (12 octets de nonce + 16 octets de tag + >= 1 octet chiffré).
    public static let tailleMinBlocAuthentifie = 29
    /// Taille maximale autorisée d'une trame (64 Ko, `ARCH-2`).
    public static let tailleMaxBlocAuthentifie = 65_536

    public let nombreMaxMessagesParFenetre: Int
    public let dureeFenetreSecondes: TimeInterval
    public let seuilEchecsAuthentificationConsecutifs: Int

    public private(set) var echecsAuthentificationConsecutifs: Int = 0
    public private(set) var nombreRejetsRapides: Int = 0

    /// Horodatages des messages acceptés par le filtre de débit au cours de la fenêtre glissante courante (en RAM).
    private var horodatagesFenetreGlissante: [Date] = []

    /// Initialise le service de limitation de débit et de rejet rapide.
    ///
    /// - Parameters:
    ///   - nombreMaxMessagesParFenetre: Plafond de messages dans la fenêtre (`10` par défaut).
    ///   - dureeFenetreSecondes: Largeur de la fenêtre glissante en secondes (`1.0` s par défaut).
    ///   - seuilEchecsAuthentificationConsecutifs: Nombre d'échecs crypto consécutifs avant blocage (`3` par défaut).
    public init(
        nombreMaxMessagesParFenetre: Int = 10,
        dureeFenetreSecondes: TimeInterval = 1.0,
        seuilEchecsAuthentificationConsecutifs: Int = 3
    ) {
        self.nombreMaxMessagesParFenetre = max(1, nombreMaxMessagesParFenetre)
        self.dureeFenetreSecondes = max(0.1, dureeFenetreSecondes)
        self.seuilEchecsAuthentificationConsecutifs = max(1, seuilEchecsAuthentificationConsecutifs)
    }

    public func evaluerMessageEntrant(
        tailleOctets: Int,
        estPairAppaire: Bool,
        estCanalOuvert: Bool,
        dateReception: Date = Date()
    ) -> DecisionFiltrageRapide {
        // 1. Rejet immédiat si le client est déjà verrouillé suite à des messages non authentifiés répétés (D2, E2).
        if echecsAuthentificationConsecutifs >= seuilEchecsAuthentificationConsecutifs {
            nombreRejetsRapides += 1
            return .rejeteClientVerrouilleApresEchecs(
                echecsConsecutifs: echecsAuthentificationConsecutifs
            )
        }

        // 2. Rejet immédiat si aucun iPhone n'est appairé et confirmé (E2).
        guard estPairAppaire else {
            nombreRejetsRapides += 1
            echecsAuthentificationConsecutifs += 1
            return .rejetePairNonAppaire
        }

        // 3. Rejet immédiat si le canal chiffré ECDH / AES-256-GCM n'est pas ouvert (E2, D2).
        guard estCanalOuvert else {
            nombreRejetsRapides += 1
            echecsAuthentificationConsecutifs += 1
            return .rejeteCanalNonOuvert
        }

        // 4. Rejet immédiat si la taille ne peut pas correspondre à un bloc AES-GCM valide (D2, D3).
        guard tailleOctets >= Self.tailleMinBlocAuthentifie,
              tailleOctets <= Self.tailleMaxBlocAuthentifie else {
            nombreRejetsRapides += 1
            echecsAuthentificationConsecutifs += 1
            return .rejeteTailleInvalide(tailleOctets)
        }

        // 5. Nettoyage de la fenêtre glissante : suppression des horodatages plus anciens que `dureeFenetreSecondes`.
        let seuilAnciennete = dateReception.addingTimeInterval(-dureeFenetreSecondes)
        horodatagesFenetreGlissante.removeAll { $0 < seuilAnciennete }

        // 6. Vérification du plafond de débit dans la fenêtre courante (contre un flood D2).
        if horodatagesFenetreGlissante.count >= nombreMaxMessagesParFenetre {
            nombreRejetsRapides += 1
            return .rejeteDebitDepasse(
                messagesDansFenetre: horodatagesFenetreGlissante.count,
                plafond: nombreMaxMessagesParFenetre
            )
        }

        // 7. Message autorisé à passer aux vérifications CryptoKit (MAC-3 et MAC-4).
        horodatagesFenetreGlissante.append(dateReception)
        return .autorise
    }

    public func signalerEchecAuthentification() {
        echecsAuthentificationConsecutifs += 1
    }

    public func signalerSuccesAuthentification() {
        echecsAuthentificationConsecutifs = 0
    }

    public func reinitialiserLimiteur() {
        echecsAuthentificationConsecutifs = 0
        nombreRejetsRapides = 0
        horodatagesFenetreGlissante.removeAll(keepingCapacity: false)
    }
}
