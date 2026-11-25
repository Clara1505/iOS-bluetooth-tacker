#if canImport(SwiftUI)
import SwiftUI

/// Vue principale de la centrale Mac (`MAC-1`, `MAC-2` et `MAC-3`).
///
/// Affiche :
/// - L'état de l'écouteur TCP local (`Network.framework` / Bonjour `_antitracker._tcp`).
/// - Le panneau d'appairage par QR code avec vérification visuelle du code court à 6 chiffres et de l'empreinte (`MAC-2`).
/// - L'état du canal chiffré (ECDH P-256 éphémère signé, HKDF-SHA256 à 1 clé par sens, AES-256-GCM) (`MAC-3`).
/// - Un filtre par niveau de gravité (`Tous`, `Info`, `Alerte`, `Critique`).
/// - L'historique des alertes reçues en mémoire vive (sans aucune persistance disque, `ARCH-7` / `I4`).
/// - Le compteur de trames rejetées en sécurité (`D2` / `D3`).
/// - Un bouton de purge immédiate en mémoire (historique + clés de session + clés d'appairage) pour la fin de séance (`MAC-7` / `I4`).
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
        VStack(alignment: .leading, spacing: 14) {
            enteteStatut
            panneauAppairageQR
            bandeauCanalChiffre
            barreOutilsFiltreEtPurge
            Divider()
            listeHistoriqueAlertes
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 600)
        .onDisappear {
            // Purge automatique dès que la fenêtre de la centrale est fermée sur le Mac prêté (MAC-7, I4, C3).
            viewModel.purgerLorsDeLaFermeture()
        }
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

    /// Panneau dédié à l'appairage par QR code et à la confirmation visuelle de l'empreinte (`MAC-2`).
    private var panneauAppairageQR: some View {
        GroupBox {
            HStack(spacing: 20) {
                switch viewModel.etatAppairage {
                case .nonAppaire:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Aucun iPhone appairé pour cette séance", systemImage: "qrcode")
                            .font(.subheadline.bold())
                        Text("Générez un QR code d'appairage éphémère en RAM pour lier votre iPhone capteur (contre S1, S4, E2).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Générer QR d'appairage") {
                        viewModel.genererQRCodeAppairage()
                    }

                case .qrCodeAffiche(let chargeQR, let donneesQR):
                    #if canImport(CoreImage) && canImport(CoreGraphics)
                    if let cgImage = GenerateurQRCode.genererImageQR(depuis: donneesQR) {
                        Image(decorative: cgImage, scale: 1.0)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .padding(6)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #endif

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Scannez ce QR code avec l'iPhone capteur", systemImage: "camera.viewfinder")
                            .font(.subheadline.bold())
                        Text("Service : \(chargeQR.nomService) (port \(chargeQR.port))")
                            .font(.caption.monospaced())
                        let empreinteMacCourte = chargeQR.empreinteClePubliqueMac.prefix(4)
                            .map { String(format: "%02X", $0) }.joined()
                        Text("Empreinte SHA-256 clé Mac : \(empreinteMacCourte)…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Régénérer QR") {
                        viewModel.genererQRCodeAppairage()
                    }

                case .attenteConfirmationEmpreinte(let codeCourt, let empreinteHex):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Vérifiez que ce code est identique sur l'iPhone (S4, H4) :", systemImage: "checkmark.shield")
                            .font(.subheadline.bold())
                        HStack(spacing: 16) {
                            Text("Code court : \(codeCourt)")
                                .font(.title3.monospaced().bold())
                                .foregroundStyle(.blue)
                            Text("Empreinte : \(empreinteHex)")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Confirmer l'empreinte") {
                        viewModel.confirmerAppairage()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refuser", role: .destructive) {
                        viewModel.refuserAppairage()
                    }

                case .appaire(let empreinteIPhoneHex):
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iPhone capteur appairé et vérifié")
                                .font(.subheadline.bold())
                            Text("Empreinte clé publique iPhone (en RAM) : \(empreinteIPhoneHex)…")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Révoquer et régénérer QR") {
                        viewModel.genererQRCodeAppairage()
                    }

                case .rejete(let raison):
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.shield.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Appairage rejeté en sécurité")
                                .font(.subheadline.bold())
                            Text(raison)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Nouveau QR d'appairage") {
                        viewModel.genererQRCodeAppairage()
                    }
                }
            }
            .padding(8)
        } label: {
            Text("Appairage sécurisé iPhone ↔ Mac (MAC-2 – Clés en RAM)")
                .font(.caption.bold())
        }
    }

    /// Bandeau indiquant l'état du canal chiffré ECDH éphémère + HKDF-SHA256 + AES-256-GCM (`MAC-3`).
    private var bandeauCanalChiffre: some View {
        GroupBox {
            HStack(spacing: 12) {
                switch viewModel.etatCanalChiffre {
                case .ferme:
                    Image(systemName: "lock.slash")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canal chiffré fermé")
                            .font(.subheadline.bold())
                        Text("En attente de l'échange ECDH P-256 éphémère signé après confirmation de l'appairage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .ouvert(let empreinteSessionHex):
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canal chiffré actif (ECDH P-256 éphémère • HKDF-SHA256 1 clé/sens • AES-256-GCM)")
                            .font(.subheadline.bold())
                        Text("ID session (RAM) : \(empreinteSessionHex)… • Dernier compteur signé accepté (MAC-4) : \(viewModel.dernierCompteurAntiRejeu)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                case .verrouille(let raison):
                    Image(systemName: "exclamationmark.lock.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canal verrouillé en sécurité")
                            .font(.subheadline.bold())
                        Text(raison)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(6)
        } label: {
            Text("Canal chiffré (MAC-3 – Confidentialité persistante I1 & Intégrité T1)")
                .font(.caption.bold())
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

            if let datePurge = viewModel.dateDernierePurge {
                Text("Purge RAM : \(datePurge.formatted(date: .omitted, time: .standard))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
            }

            Button(role: .destructive) {
                viewModel.purgerHistoriqueSession()
            } label: {
                Label("Purger la session et les clés (RAM)", systemImage: "trash")
            }
            .disabled(
                viewModel.alertesRecues.isEmpty &&
                viewModel.nombreTramesRejetees == 0 &&
                viewModel.etatAppairage == .nonAppaire &&
                viewModel.etatCanalChiffre == .ferme
            )
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
