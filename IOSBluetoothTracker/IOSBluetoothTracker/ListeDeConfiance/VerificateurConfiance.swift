import Foundation

/// Indique si un appareil détecté figure dans la liste de confiance.
struct VerificateurConfiance {

    private let stockage: StockageListeDeConfiance
    private let hacheur: HacheurIdentifiant

    init(stockage: StockageListeDeConfiance, hacheur: HacheurIdentifiant) {
        self.stockage = stockage
        self.hacheur = hacheur
    }

    /// Lit la liste une seule fois et renvoie les identifiants hachés de confiance.
    /// Si la liste ne peut pas être lue ou vérifiée, renvoie un ensemble vide :
    /// tous les appareils sont alors traités comme inconnus (choix prudent).
    func idsDeConfiance() -> Set<Data> {
        guard let contenu = try? stockage.lire() else {
            return []
        }
        return Set(contenu.appareils.map(\.idHache))
    }

    /// - Parameters:
    ///   - appareil: appareil détecté pendant le balayage.
    ///   - ids: ensemble obtenu avec `idsDeConfiance()`.
    func estDeConfiance(_ appareil: AppareilDetecte, parmi ids: Set<Data>) -> Bool {
        ids.contains(hacheur.hacher(appareil.identifiantSysteme))
    }
}