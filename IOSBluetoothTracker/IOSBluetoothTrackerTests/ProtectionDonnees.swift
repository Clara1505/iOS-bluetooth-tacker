import Foundation
import SwiftUI
import UIKit
import Testing
@testable import TrackerBluetooth

@Suite("Protections des données (TRU-4)")
struct ProtectionDonneesTests {

    @Test("Le contenu est masqué dès que l'app n'est plus active")
    func masquageSelonLaPhase() {
        #expect(PolitiqueMasquage.doitMasquer(.active) == false)
        #expect(PolitiqueMasquage.doitMasquer(.inactive))
        #expect(PolitiqueMasquage.doitMasquer(.background))
    }

    @Test("Un fichier écrit avec la protection « Complete » est reconnu")
    func fichierProtegeComplete() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tru4-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("{}".utf8).write(to: url, options: [.atomic, .completeFileProtection])

        // Sur simulateur, l'attribut peut ne pas être appliqué : ce test doit être validé sur iPhone.
        #expect(try VerificationProtection.estProtegeComplete(url))
    }

    @Test("Un fichier sans protection est signalé")
    func fichierSansProtection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tru4-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("{}".utf8).write(to: url, options: [.atomic, .noFileProtection])

        #expect(try VerificationProtection.estProtegeComplete(url) == false)
    }

    @Test("La copie locale est lisible sur cet appareil")
    @MainActor
    func copieLocaleLisible() {
        PressePapiersLocal.copier("Sac 2 Bleu")

        #expect(UIPasteboard.general.string == "Sac 2 Bleu")
    }
}