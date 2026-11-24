import SwiftUI

struct BalayageVue: View {
    @State private var vueModele: BalayageVueModele

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
                Text("Contrôle impossible")
            case nil:
                EmptyView()
            }
        }
        .padding()
    }
}

#Preview {
    BalayageVue(service: FauxServiceBalayage(resultat: .controleImpossible(.bluetoothCoupe)))
}