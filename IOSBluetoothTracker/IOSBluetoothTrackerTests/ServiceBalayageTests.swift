//
//  ServiceBalayageTests.swift
//  IOSBluetoothTrackerTests
//

import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Tests du contrat `ServiceBalayage` et du vue-modèle, avec le faux service (données fictives).
@MainActor
struct ServiceBalayageTests {
    /// Crée un appareil fictif.
    private func appareilFictif(nom: String? = "Appareil fictif", rssi: Int = -60) -> AppareilDetecte {
        AppareilDetecte(
            identifiantSysteme: UUID(),
            nomAnnonce: nom,
            rssi: rssi,
            premiereDetection: .now,
            derniereDetection: .now
        )
    }

    @Test func renvoieLesAppareilsPrevus() async {
        let appareil = appareilFictif()
        let service: any ServiceBalayage = FauxServiceBalayage(resultat: .complet([appareil]))
        let resultat = await service.lancerBalayage(duree: 30)
        #expect(resultat == .complet([appareil]))
    }

    @Test func remonteControleImpossibleQuandLeBluetoothEstCoupe() async {
        let service: any ServiceBalayage = FauxServiceBalayage(resultat: .controleImpossible(.bluetoothCoupe))
        let resultat = await service.lancerBalayage(duree: 30)
        #expect(resultat == .controleImpossible(.bluetoothCoupe))
    }

    /// D4 : un contrôle impossible ne doit jamais ressembler à une liste vide.
    @Test func controleImpossibleNestPasUneListeVide() {
        #expect(ResultatBalayage.controleImpossible(.interrompu) != .complet([]))
    }

    @Test func leVueModelePublieLeResultat() async {
        let vueModele = BalayageVueModele(
            service: FauxServiceBalayage(resultat: .controleImpossible(.permissionRefusee))
        )
        #expect(vueModele.resultat == nil)
        await vueModele.lancerControle()
        #expect(vueModele.resultat == .controleImpossible(.permissionRefusee))
        #expect(vueModele.enCours == false)
    }
}
