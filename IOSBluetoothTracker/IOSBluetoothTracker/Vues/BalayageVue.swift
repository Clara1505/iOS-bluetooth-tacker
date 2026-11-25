//
//  BalayageVue.swift
//  IOSBluetoothTracker
//

import SwiftUI

/// Écran principal : bouton « Contrôle de sécurité » et résultat du dernier contrôle.
struct BalayageVue: View {
    @State private var vueModele: BalayageVueModele

    /// - Parameter service: service de balayage à utiliser.
    init(service: any ServiceBalayage) {
        _vueModele = State(initialValue: BalayageVueModele(service: service))
    }

    var body: some View {
        VStack(spacing: 16) {
            Button("Contrôle de sécurité") {
                Task { await vueModele.lancerControle() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vueModele.enCours)

            if vueModele.enCours {
                ProgressView("Balayage en cours…")
            }

            switch vueModele.resultat {
            case .complet(let appareils, let plafondAtteint):
                if plafondAtteint {
                    // D1 : la liste a été limitée, l'utilisateur doit le savoir.
                    Label(
                        "Trop d'appareils autour de vous : seuls les \(appareils.count) signaux les plus forts sont affichés.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                if appareils.isEmpty {
                    Text("Aucun appareil détecté")
                } else {
                    BandeauNiveauVue(niveau: vueModele.niveauGlobal)
                    ListeAppareilsVue(evaluations: vueModele.evaluations)
                }
            case .controleImpossible(let raison):
                // D4 : jamais « aucun appareil » quand le contrôle n'a pas abouti.
                Label(raison.message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case nil:
                Spacer()
            }
        }
        .padding()
    }
}

/// Bandeau résumant le niveau le plus élevé du dernier contrôle.
struct BandeauNiveauVue: View {
    /// Niveau le plus élevé, ou `nil` s'il n'y a aucun appareil inconnu.
    let niveau: NiveauAlerte?

    var body: some View {
        switch niveau {
        case .alerte:
            Label("Alerte : un appareil inconnu est resté près de vous pendant tout le contrôle.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .info:
            Label("Appareils inconnus à proximité, sans signe de suivi.", systemImage: "info.circle")
                .foregroundStyle(.blue)
        case nil:
            Label("Aucun appareil inconnu.", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
        }
    }
}

/// Liste des appareils détectés, du plus grave au moins grave puis du signal le plus fort au plus faible.
struct ListeAppareilsVue: View {
    let evaluations: [AppareilEvalue]

    var body: some View {
        List {
            Section("\(evaluations.count) appareil(s) détecté(s)") {
                ForEach(evaluations) { evaluation in
                    HStack {
                        // L'identifiant n'est pas affiché : il n'aide pas l'utilisateur
                        // et c'est une donnée à protéger (I5).
                        Text(evaluation.appareil.nomAnnonce ?? "Appareil sans nom")
                        Spacer()
                        Text("\(evaluation.appareil.rssi) dBm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        EtiquetteNiveauVue(niveau: evaluation.niveau)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Petite étiquette de niveau affichée sur chaque ligne.
struct EtiquetteNiveauVue: View {
    let niveau: NiveauAlerte?

    var body: some View {
        switch niveau {
        case .alerte:
            Text("Alerte").font(.caption.bold()).foregroundStyle(.red)
        case .info:
            Text("Info").font(.caption).foregroundStyle(.blue)
        case nil:
            Text("Confiance").font(.caption).foregroundStyle(.green)
        }
    }
}

extension RaisonEchec {
    /// Message affiché à l'utilisateur quand le contrôle est impossible.
    var message: String {
        switch self {
        case .bluetoothCoupe:
            return "Contrôle impossible : le Bluetooth est éteint."
        case .permissionRefusee:
            return "Contrôle impossible : l'accès au Bluetooth est refusé. Autorisez-le dans Réglages."
        case .interrompu:
            return "Contrôle impossible : le balayage a été interrompu. Relancez le contrôle."
        case .nonSupporte:
            return "Contrôle impossible : cet appareil ne gère pas le Bluetooth Low Energy."
        }
    }
}

#if DEBUG
/// Appareils fictifs pour les aperçus (aucune donnée réelle).
private let appareilsFictifs = [
    AppareilDetecte(identifiantSysteme: UUID(), nomAnnonce: "Casque fictif", rssi: -48,
                    premiereDetection: .now, derniereDetection: .now + 25),
    AppareilDetecte(identifiantSysteme: UUID(), nomAnnonce: nil, rssi: -77,
                    premiereDetection: .now, derniereDetection: .now),
]

#Preview("Contrôle impossible") {
    BalayageVue(service: FauxServiceBalayage(resultat: .controleImpossible(.bluetoothCoupe)))
}

#Preview("Liste") {
    BalayageVue(service: FauxServiceBalayage(resultat: .complet(appareilsFictifs)))
}

#Preview("Plafond atteint") {
    BalayageVue(service: FauxServiceBalayage(resultat: .complet(appareilsFictifs, plafondAtteint: true)))
}
#endif
