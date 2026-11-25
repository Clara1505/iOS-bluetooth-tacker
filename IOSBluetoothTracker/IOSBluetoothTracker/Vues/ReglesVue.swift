import SwiftUI
import UIKit

/// Écran de réglages (version minimale).
struct ReglesVue: View {
    @Environment(\.openURL) private var ouvrirURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Bluetooth") {
                    Text("Le Bluetooth n'est utilisé que pendant un contrôle de sécurité.")
                    Button("Ouvrir les réglages de l'iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            ouvrirURL(url)
                        }
                    }
                }

                Section("Liste de confiance") {
                    Text("La liste est chiffrée et enregistrée sur cet iPhone. La modifier demande Face ID ou le code de l'iPhone.")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}