#if canImport(SwiftUI)
import SwiftUI
import CentraleMacCore
#if canImport(AppKit)
import AppKit
#endif

/// Point d'entrée principal de l'application Centrale Mac (`MAC-1` à `MAC-4` et `MAC-7`).
///
/// Lance la fenêtre SwiftUI de la centrale en injectant `ServiceReceptionAlertes`
/// (`Network.framework` en TCP + Bonjour `_antitracker._tcp`) dans `CentraleMacViewModel`.
/// Toutes les données restent uniquement en mémoire vive (RAM) pendant la séance (`ARCH-7`, `I4`)
/// et sont purgées automatiquement à la fermeture de l'application (`MAC-7`, remarque `C3`).
@main
struct CentraleMacApplication: App {
    @State private var viewModel = CentraleMacViewModel(
        serviceReception: ServiceReceptionAlertes()
    )

    init() {
        #if canImport(AppKit)
        // Permet à l'exécutable SwiftPM d'afficher sa fenêtre au premier plan sur macOS.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup("Centrale Anti-Traceur (Mac)") {
            CentraleMacView(viewModel: viewModel)
                #if canImport(AppKit)
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    // Purge automatique à la fermeture de l'application (Cmd+Q / fermeture processus, MAC-7 / C3).
                    viewModel.purgerLorsDeLaFermeture()
                }
                #endif
        }
    }
}
#endif
