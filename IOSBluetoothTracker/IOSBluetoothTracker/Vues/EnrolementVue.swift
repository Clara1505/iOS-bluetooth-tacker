import SwiftUI

/// Écran pour nommer un appareil détecté et l'ajouter à la liste de confiance .
struct EnrolementVue: View {
    @StateObject private var vueModele: EnrolementVueModele
    @Environment(\.dismiss) private var fermer
    private let appareil: AppareilDetecte

    /// - Parameters:
    ///   - appareil: appareil détecté à enrôler.
    ///   - vueModele: vue-modèle de l'enrôlement.
    init(appareil: AppareilDetecte, vueModele: EnrolementVueModele) {
        self.appareil = appareil
        _vueModele = StateObject(wrappedValue: vueModele)
    }

    var body: some View {
        Form {
            Section {
                TextField("Ex. : Sac bleu", text: $vueModele.nomSaisi)
                    .disableAutocorrection(true)
            } header: {
                Text("Nom de l'appareil")
            } footer: {
                Text("15 caractères au maximum : lettres sans accent, chiffres et espaces.")
            }

            Section {
                Button("Ajouter à ma liste") {
                    vueModele.enroler(appareil)
                }
            }

            switch vueModele.etat {
            case .saisie:
                EmptyView()
            case .termine:
                Section {
                    Label("Appareil ajouté.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Button("Fermer") { fermer() }
                }
            case .nomInvalide(let erreur):
                Section {
                    Label(erreur.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            case .authentificationRefusee:
                Section {
                    Label("Authentification refusée : l'appareil n'a pas été ajouté.", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            case .erreur:
                Section {
                    Label("Une erreur est survenue : l'appareil n'a pas été ajouté.", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Nouvel appareil")
    }
}