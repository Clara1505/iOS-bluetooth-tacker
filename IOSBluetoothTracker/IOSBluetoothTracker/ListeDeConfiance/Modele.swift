import Foundation

/// Appareil de la liste de confiance. L'identifiant est haché (HMAC-SHA256), jamais brut (I5).
struct AppareilDeConfiance: Codable, Equatable {
    /// Identifiant haché (HMAC-SHA256) de l'appareil.
    let idHache: Data
    /// Nom donné par l'utilisateur lors de l'enrôlement (TRU-1).
    let nom: String
    /// Date d'ajout à la liste.
    let ajouteLe: Date
}

/// Action enregistrée dans l'historique des modifications (R2).
enum ActionHistorique: String, Codable {
    case ajout
    case suppression
}

/// Mode d'authentification utilisé pour une modification (R2).
///
/// `biometrie` couvre Face ID et Touch ID (l'iPhone 7 n'a que Touch ID, PM-11).
/// La valeur sérialisée reste « faceID » : le format stocké et signé ne change pas,
/// donc les listes et historiques déjà écrits restent lisibles et leur signature valide.
enum ModeAuthentification: String, Codable {
    case biometrie = "faceID"
    case code
}

/// Entrée de l'historique des modifications de la liste (R2).
struct EntreeHistorique: Codable, Equatable {
    let date: Date
    let action: ActionHistorique
    let nomAppareil: String
    let mode: ModeAuthentification
}

/// Contenu de la liste de confiance : appareils et historique, chiffrés ensemble.
struct ContenuListe: Codable, Equatable {
    /// Nombre maximal d'entrées conservées dans l'historique (R2).
    static let tailleMaxHistorique = 20

    var appareils: [AppareilDeConfiance] = []
    var historique: [EntreeHistorique] = []

    /// Ajoute une entrée à l'historique, en ne gardant que les plus récentes.
    /// - Parameter entree: l'entrée à ajouter.
    mutating func ajouterHistorique(_ entree: EntreeHistorique) {
        historique.append(entree)
        if historique.count > Self.tailleMaxHistorique {
            historique.removeFirst(historique.count - Self.tailleMaxHistorique)
        }
    }
}

/// Erreurs de la liste de confiance.
/// Toute erreur signifie qu'aucun appareil n'est considéré comme de confiance (échec en sécurité).
enum ErreurListeDeConfiance: Error, Equatable {
    /// Le fichier est absent, illisible ou mal formé.
    case fichierIllisible
    /// Le déchiffrement AES-GCM a échoué : fichier altéré ou clé absente.
    case dechiffrementEchoue
    /// La signature ne correspond pas aux données signées.
    case signatureInvalide
    /// La version lue est plus ancienne que celle mémorisée : retour arrière refusé.
    case versionPerimee
    /// L'authentification (biométrie ou code) a échoué ou été annulée.
    case authentificationEchouee
    /// Erreur d'un composant système (Keychain, Secure Enclave).
    case erreurSysteme
}

/// Erreurs de validation d'un nom d'appareil.
enum ErreurNomAppareil: Error, Equatable {
    /// Le nom est vide après suppression des espaces en début et fin.
    case vide
    /// Le nom dépasse la longueur maximale.
    case tropLong
    /// Le nom contient un caractère interdit (accent, emoji, ponctuation, autre alphabet).
    case caractereNonAutorise
}

/// Nom d'un appareil de la liste de confiance.
/// Exigences : 1 à 15 caractères affichés ; lettres ASCII sans accent, chiffres et espaces uniquement.
/// Les emojis et les accents sont refusés.
struct NomAppareil: Equatable {
    /// Longueur maximale, en caractères affichés.
    static let longueurMax = 15

    /// Valeur validée, sans espaces en début ni en fin.
    let valeur: String

    /// - Parameter brut: nom saisi par l'utilisateur.
    /// - Throws: `ErreurNomAppareil` si le nom est vide, trop long, ou contient un caractère interdit.
    init(_ brut: String) throws {
        let propre = brut.trimmingCharacters(in: .whitespaces)
        guard !propre.isEmpty else {
            throw ErreurNomAppareil.vide
        }
        guard propre.count <= Self.longueurMax else {
            throw ErreurNomAppareil.tropLong
        }
        for scalaire in propre.unicodeScalars where !Self.estAutorise(scalaire) {
            throw ErreurNomAppareil.caractereNonAutorise
        }
        valeur = propre
    }

    /// Indique si un caractère est autorisé dans un nom d'appareil.
    /// - Parameter scalaire: caractère Unicode à tester.
    /// - Returns: `true` seulement pour une lettre ASCII sans accent, un chiffre ou un espace.
    private static func estAutorise(_ scalaire: Unicode.Scalar) -> Bool {
        guard scalaire.isASCII else {
            return false
        }
        let valeur = scalaire.value
        let estLettre = (0x41...0x5A).contains(valeur) || (0x61...0x7A).contains(valeur)
        let estChiffre = (0x30...0x39).contains(valeur)
        return estLettre || estChiffre || valeur == 0x20
    }
}
