import Foundation

/// Niveau de gravité d'une alerte émise par le capteur iPhone.
///
/// Conforme à la spécification `docs/architecture/niveaux-alerte.md` (ARCH-4).
public enum NiveauAlerte: String, Codable, CaseIterable, Sendable {
    /// Appareil inconnu observé lors d'un seul balayage complet.
    case info
    /// Même appareil inconnu observé sur au moins deux balayages complets dans la fenêtre de surveillance.
    case alerte
    /// Traceur identifié (type Find My) ou critère critique défini après le spike ARCH-6.
    case critique

    /// Libellé lisible affiché dans l'interface de la centrale Mac.
    public var libelle: String {
        switch self {
        case .info:
            return "Info"
        case .alerte:
            return "Alerte"
        case .critique:
            return "Critique"
        }
    }
}

/// Erreurs de validation d'une alerte reçue depuis une source externe (réseau local F3).
///
/// Menaces STRIDE visées :
/// - `D3` : rejet propre de toute donnée malformée sans déballage forcé (`!`, `try!`).
/// - `I5` : vérification que l'identifiant est bien un condensat HMAC-SHA256 de 32 octets.
public enum ErreurValidationAlerte: Error, Equatable, Sendable {
    /// La taille de `idHache` ne correspond pas aux 32 octets d'un HMAC-SHA256.
    case tailleIdHacheInvalide(Int)
    /// La liste des balayages de référence est vide ou dépasse le plafond autorisé.
    case nombreBalayagesRefsInvalide(Int)
}

/// Alerte de sécurité générée par l'iPhone et transmise à la centrale Mac.
///
/// Conforme au modèle `docs/architecture/modele-donnees.md` (§2.5, ARCH-3) :
/// - Aucun identifiant Bluetooth brut n'est présent : seul `idHache` (HMAC-SHA256 de 32 octets) est manipulé (menace `I5`).
/// - Le Mac ne recalcule jamais le niveau d'une alerte : il valide, vérifie et affiche l'événement reçu.
public struct Alerte: Identifiable, Codable, Equatable, Sendable {
    /// Taille exacte attendue pour un condensat HMAC-SHA256 (32 octets / 256 bits).
    public static let tailleAttendueIdHache = 32
    /// Plafond de sécurité sur le nombre de références de balayages dans une seule alerte (contre `D2` / `D3`).
    public static let nombreMaxBalayagesRefs = 64

    /// Identifiant unique de l'événement d'alerte.
    public let id: UUID
    /// Niveau de gravité évalué par l'iPhone (`info`, `alerte`, `critique`).
    public let niveau: NiveauAlerte
    /// Condensat HMAC-SHA256 (32 octets) de l'identifiant de l'appareil observé.
    public let idHache: Data
    /// Identifiants des balayages complets ayant servi à déclencher cette alerte.
    public let balayagesRefs: [UUID]
    /// Horodatage de génération de l'alerte sur l'iPhone.
    public let date: Date

    /// Initialise une alerte en mémoire.
    ///
    /// - Parameters:
    ///   - id: Identifiant unique de l'alerte.
    ///   - niveau: Niveau de gravité (`info`, `alerte`, `critique`).
    ///   - idHache: Condensat HMAC-SHA256 (32 octets).
    ///   - balayagesRefs: Liste des identifiants de balayages associés.
    ///   - date: Date d'émission de l'alerte.
    public init(
        id: UUID = UUID(),
        niveau: NiveauAlerte,
        idHache: Data,
        balayagesRefs: [UUID],
        date: Date = Date()
    ) {
        self.id = id
        self.niveau = niveau
        self.idHache = idHache
        self.balayagesRefs = balayagesRefs
        self.date = date
    }

    /// Vérifie que les champs de l'alerte désérialisée depuis le réseau respectent les contraintes de format et de taille.
    ///
    /// Conformément à `CLAUDE.md` (§7), toute donnée venant de l'extérieur (frontière `F3`) est validée avant utilisation.
    ///
    /// - Throws: `ErreurValidationAlerte` si `idHache` ne fait pas exactement 32 octets
    ///           ou si `balayagesRefs` est vide ou dépasse `nombreMaxBalayagesRefs`.
    public func validerFormat() throws {
        guard idHache.count == Self.tailleAttendueIdHache else {
            throw ErreurValidationAlerte.tailleIdHacheInvalide(idHache.count)
        }
        guard !balayagesRefs.isEmpty, balayagesRefs.count <= Self.nombreMaxBalayagesRefs else {
            throw ErreurValidationAlerte.nombreBalayagesRefsInvalide(balayagesRefs.count)
        }
    }

    /// Représentation hexadécimale abrégée (8 premiers caractères) du condensat `idHache` pour l'affichage.
    ///
    /// Ne révèle aucun identifiant Bluetooth brut (`I5`) et ne sert qu'à distinguer visuellement deux entrées dans l'interface Mac.
    public var empreinteCourteAffichage: String {
        let prefixe = idHache.prefix(4)
        return prefixe.map { String(format: "%02x", $0) }.joined()
    }
}
