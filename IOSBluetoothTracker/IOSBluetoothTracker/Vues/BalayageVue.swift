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
            .disabled(vueModele.enCours)

            if vueModele.enCours {
                ProgressView("Balayage en cours…")
            }

            switch vueModele.resultat {
            case .complet(let appareils):
                Text(appareils.isEmpty ? "Aucun appareil détecté" : "\(appareils.count) appareil(s) détecté(s)")
            case .controleImpossible:
                // D4 : jamais « aucun appareil » quand le contrôle n'a pas abouti.
                Text("Contrôle impossible")
            case nil:
                EmptyView()
            }
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    BalayageVue(service: FauxServiceBalayage(resultat: .controleImpossible(.bluetoothCoupe)))
}
#endif
