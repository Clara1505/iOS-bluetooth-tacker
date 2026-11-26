import SwiftUI
import UIKit

/// Écran de réglages (version minimale).
struct ReglesVue: View {
    @Environment(\.openURL) private var ouvrirURL

    var body: some View {
        // NavigationView : NavigationStack demande iOS 16 (cible minimale iOS 15, PM-11).
        // Le style .stack évite l'affichage en deux colonnes sur grand écran.
        NavigationView {
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
                    Text("La liste est chiffrée et enregistrée sur cet iPhone. La modifier demande la biométrie (Face ID ou Touch ID) ou le code de l'iPhone.")
                }
            }
            .navigationTitle("Réglages")
        }
        .navigationViewStyle(.stack)
    }
}