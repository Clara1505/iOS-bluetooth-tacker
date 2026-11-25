import SwiftUI

/// Écran de la liste de confiance : appareils de l'utilisateur et historique des modifications.
struct ListeConfianceVue: View {
    @State private var vueModele: ListeConfianceVueModele

    /// - Parameter vueModele: vue-modèle de la liste.
    init(vueModele: ListeConfianceVueModele) {
        _vueModele = State(initialValue: vueModele)
    }

    var body: some View {
        NavigationStack {
            List {
                if vueModele.listeIllisible {
                    // Jamais « liste vide » quand la liste n'a pas pu être vérifiée.
                    Section {
                        Label(
                            "La liste de confiance ne peut pas être vérifiée. Aucun appareil n'est considéré comme de confiance.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                    }
                } else {
                    Section("Mes appareils") {
                        if vueModele.contenu.appareils.isEmpty {
                            Text("Aucun appareil de confiance")
                        }
                        ForEach(vueModele.contenu.appareils, id: \.idHache) { appareil in
                            VStack(alignment: .leading) {
                                Text(appareil.nom)
                                Text("Ajouté le \(appareil.ajouteLe.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Retirer", role: .destructive) {
                                    vueModele.supprimer(appareil)
                                }
                            }
                        }
                    }

                    Section("Historique") {
                        if vueModele.contenu.historique.isEmpty {
                            Text("Aucune modification")
                        }
                        ForEach(Array(vueModele.contenu.historique.enumerated()), id: \.offset) { _, entree in
                            Text("\(entree.action.libelle) : \(entree.nomAppareil) (\(entree.mode.libelle), \(entree.date.formatted(date: .abbreviated, time: .shortened)))")
                                .font(.caption)
                        }
                    }
                }

                if let message = vueModele.messageErreur {
                    Section {
                        Label(message, systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Appareils de confiance")
            .onAppear { vueModele.charger() }
        }
    }
}

extension ActionHistorique {
    /// Libellé affiché dans l'historique.
    var libelle: String {
        switch self {
        case .ajout: return "Ajout"
        case .suppression: return "Retrait"
        }
    }
}

extension ModeAuthentification {
    /// Libellé affiché dans l'historique.
    var libelle: String {
        switch self {
        case .faceID: return "Face ID"
        case .code: return "code"
        }
    }
}