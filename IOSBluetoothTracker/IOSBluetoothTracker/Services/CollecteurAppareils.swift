import Foundation

struct CollecteurAppareils: Sendable {
    private var parIdentifiant: [UUID: AppareilDetecte] = [:]

    /// Enregistre une détection et met à jour l'appareil s'il a déjà été vu.
    /// Un RSSI invalide ne fait pas disparaître l'appareil : on garde la valeur précédente ou le minimum.
    mutating func enregistrer(identifiant: UUID, nom: String?, rssi: Int, date: Date) {
        let existant = parIdentifiant[identifiant]
        let rssiRetenu = ReglesBalayage.rssiValide(rssi)
            ? rssi
            : (existant?.rssi ?? ReglesBalayage.rssiMinimum)
        parIdentifiant[identifiant] = AppareilDetecte(
            identifiantSysteme: identifiant,
            nomAnnonce: nom ?? existant?.nomAnnonce,
            rssi: rssiRetenu,
            premiereDetection: existant?.premiereDetection ?? date,
            derniereDetection: date
        )
    }

    /// Appareils détectés, du signal le plus fort au plus faible.
    var appareils: [AppareilDetecte] {
        parIdentifiant.values.sorted { $0.rssi > $1.rssi }
    }

    mutating func vider() {
        parIdentifiant.removeAll()
    }
}