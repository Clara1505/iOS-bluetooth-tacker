import Foundation

/// Règle de purge glissante : chaque donnée est supprimée 72 h après sa collecte (CHOIX_CRYPTO §3.5, menace I5).
/// Ne s'applique pas à la liste de confiance ni à son historique (§3.5, exception).
enum PolitiquePurge {

    /// Durée de conservation : 72 heures.
    static let dureeConservation: TimeInterval = 72 * 3600

    /// - Parameters:
    ///   - collecteLe: date de collecte de la donnée.
    ///   - maintenant: date courante.
    /// - Returns: `true` si la donnée a 72 h ou plus. Une date de collecte dans le futur
    ///   (horloge reculée) est aussi considérée comme expirée, par minimisation.
    static func estExpire(collecteLe: Date, maintenant: Date) -> Bool {
        collecteLe > maintenant || maintenant.timeIntervalSince(collecteLe) >= dureeConservation
    }

    /// - Parameters:
    ///   - elements: données collectées.
    ///   - dateCollecte: date de collecte d'une donnée.
    ///   - maintenant: date courante.
    /// - Returns: les données qui ne sont pas expirées.
    static func purger<Element>(
        _ elements: [Element],
        dateCollecte: (Element) -> Date,
        maintenant: Date
    ) -> [Element] {
        elements.filter { !estExpire(collecteLe: dateCollecte($0), maintenant: maintenant) }
    }
}