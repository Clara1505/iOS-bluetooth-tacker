#if canImport(SwiftUI)
import SwiftUI

/// Vue principale de la centrale Mac (`MAC-1`).
///
/// Affiche :
/// - L'état de l'écouteur TCP local (`Network.framework` / Bonjour `_antitracker._tcp`).
/// - Un filtre par niveau de gravité (`Tous`, `Info`, `Alerte`, `Critique`).
/// - L'historique des alertes reçues en mémoire vive (sans aucune persistance disque, `ARCH-7` / `I4`).
/// - Le compteur de trames rejetées en sécurité (`D2` / `D3`).
/// - Un bouton de purge immédiate en mémoire pour la fin de séance (`MAC-7` / `I4`).
public struct CentraleMacView: View {
    @State private var viewModel: CentraleMacViewModel
    @State private var filtreNiveau: NiveauAlerte? = nil

    /// Initialise la vue de la centrale avec son Vue-Modèle.
    ///
    /// - Parameter viewModel: Le Vue-Modèle de la centrale Mac.
    public init(viewModel: CentraleMacViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            enteteStatut
            barreOutilsFiltreEtPurge
            Divider()
            listeHistoriqueAlertes
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 460)
    }

    // MARK: - Sous-vues

    /// Bandeau supérieur indiquant l'état du serveur TCP et les actions de démarrage / arrêt.
    private var enteteStatut: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(couleurEtatServeur)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Centrale Anti-Traceur (Mac prêté – Session en RAM uniquement)")
                    .font(.headline)
                Text(texteEtatServeur)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.nombreTramesRejetees > 0 {
                Text("Trames rejetées : \(viewModel.nombreTramesRejetees)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            Button("Démarrer") {
                viewModel.demarrerCentrale()
            }
            .disabled(estServeurActif)

            Button("Arrêter") {
                viewModel.arreterCentrale()
            }
            .disabled(!estServeurActif)
        }
    }

    /// Barre de filtrage par niveau d'alerte et bouton de purge de fin de séance (`MAC-7`).
    private var barreOutilsFiltreEtPurge: some View {
        HStack {
            Picker("Niveau :", selection: $filtreNiveau) {
                Text("Tous (\(viewModel.alertesRecues.count))").tag(NiveauAlerte?.none)
                ForEach(NiveauAlerte.allCases, id: \.self) { niveau in
                    Text(niveau.libelle).tag(NiveauAlerte?.some(niveau))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer()

            Button(role: .destructive) {
                viewModel.purgerHistoriqueSession()
            } label: {
                Label("Purger la session (RAM)", systemImage: "trash")
            }
            .disabled(viewModel.alertesRecues.isEmpty && viewModel.nombreTramesRejetees == 0)
        }
    }

    /// Liste des alertes reçues en mémoire pendant la séance.
    @ViewBuilder
    private var listeHistoriqueAlertes: some View {
        let alertes = viewModel.alertesFiltrees(par: filtreNiveau)

        if alertes.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Aucune alerte en mémoire pour ce filtre.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Les alertes reçues de l'iPhone s'affichent ici sans être enregistrées sur le disque du Mac prêté.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(alertes) { alerte in
                ligneAlerte(alerte)
            }
        }
    }

    /// Ligne individuelle représentant une alerte reçue.
    private func ligneAlerte(_ alerte: Alerte) -> some View {
        HStack(spacing: 14) {
            Text(alerte.niveau.libelle.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(couleurNiveau(alerte.niveau))
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text("Appareil (HMAC abrégé) : \(alerte.empreinteCourteAffichage)…")
                    .font(.body.monospaced())
                Text("Balayages associés : \(alerte.balayagesRefs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(alerte.date.formatted(date: .omitted, time: .standard))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Aides d'affichage

    private var estServeurActif: Bool {
        switch viewModel.etatServeur {
        case .enEcoute, .clientConnecte, .demarrage:
            return true
        case .arrete, .erreur:
            return false
        }
    }

    private var texteEtatServeur: String {
        switch viewModel.etatServeur {
        case .arrete:
            return "Serveur arrêté"
        case .demarrage:
            return "Démarrage de l'écouteur TCP..."
        case .enEcoute(let port):
            return "En écoute TCP sur le port \(port) (Bonjour : _antitracker._tcp)"
        case .clientConnecte(let port):
            return "Capteur iPhone connecté sur le port \(port)"
        case .erreur(let description):
            return "Erreur : \(description)"
        }
    }

    private var couleurEtatServeur: Color {
        switch viewModel.etatServeur {
        case .arrete:
            return .gray
        case .demarrage:
            return .yellow
        case .enEcoute:
            return .blue
        case .clientConnecte:
            return .green
        case .erreur:
            return .red
        }
    }

    private func couleurNiveau(_ niveau: NiveauAlerte) -> Color {
        switch niveau {
        case .info:
            return .blue
        case .alerte:
            return .orange
        case .critique:
            return .red
        }
    }
}
#endif
