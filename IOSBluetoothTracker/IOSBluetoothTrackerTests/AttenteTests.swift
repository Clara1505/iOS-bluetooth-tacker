import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Tests de l'attente compatible iOS 15 (PM-11).
@Suite("Attente asynchrone (PM-11)")
struct AttenteTests {

    @Test("30 secondes valent 30 milliards de nanosecondes")
    func dureeNormale() {
        #expect(Attente.nanosecondes(pour: 30) == 30_000_000_000)
    }

    @Test("Une durée fractionnaire est convertie")
    func dureeFractionnaire() {
        #expect(Attente.nanosecondes(pour: 0.5) == 500_000_000)
    }

    @Test("Une durée nulle, négative ou NaN donne zéro")
    func dureesInvalides() {
        #expect(Attente.nanosecondes(pour: 0) == 0)
        #expect(Attente.nanosecondes(pour: -5) == 0)
        #expect(Attente.nanosecondes(pour: .nan) == 0)
    }

    @Test("Une durée démesurée est bornée sans dépassement")
    func dureesExtremes() {
        let maximum = UInt64(Attente.dureeMaximale * 1_000_000_000)
        #expect(Attente.nanosecondes(pour: .infinity) == maximum)
        #expect(Attente.nanosecondes(pour: .greatestFiniteMagnitude) == maximum)
        #expect(Attente.nanosecondes(pour: 1_000_000) == maximum)
    }

    @Test("Une attente courte se termine")
    func attenteCourte() async throws {
        try await Attente.dormir(secondes: 0.01)
    }

    @Test("Une tâche annulée pendant l'attente lève CancellationError")
    func annulation() async {
        let tache = Task { try await Attente.dormir(secondes: 30) }
        tache.cancel()
        do {
            try await tache.value
            Issue.record("L'attente aurait dû être interrompue")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
