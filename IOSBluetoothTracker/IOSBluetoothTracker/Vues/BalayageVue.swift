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
                    ListeAppareilsVue(appareils: appareils)
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

/// Liste des appareils détectés, du signal le plus fort au plus faible.
struct ListeAppareilsVue: View {
    let appareils: [AppareilDetecte]

    var body: some View {
        List {
            Section("\(appareils.count) appareil(s) détecté(s)") {
                ForEach(appareils) { appareil in
                    HStack {
                        // L'identifiant n'est pas affiché : il n'aide pas l'utilisateur
                        // et c'est une donnée à protéger (I5).
                        Text(appareil.nomAnnonce ?? "Appareil sans nom")
                        Spacer()
                        Text("\(appareil.rssi) dBm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                    premiereDetection: .now, derniereDetection: .now),
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
