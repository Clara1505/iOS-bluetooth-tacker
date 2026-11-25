//
//  ReglesBalayageTests.swift
//  IOSBluetoothTrackerTests
//

import Testing
@testable import IOSBluetoothTracker

/// Tests des règles pures du balayage : contrôle impossible (D4), RSSI, nom annoncé (T5).
@MainActor
struct ReglesBalayageTests {
    @Test(arguments: [
        (EtatBluetooth.eteint, RaisonEchec.bluetoothCoupe),
        (.nonAutorise, .permissionRefusee),
        (.nonSupporte, .nonSupporte),
        (.inconnu, .interrompu),
    ])
    func unEtatNonAllumeRendLeControleImpossible(etat: EtatBluetooth, raison: RaisonEchec) {
        #expect(ReglesBalayage.raisonEchec(pour: etat) == raison)
    }

    @Test func leBluetoothAllumePermetLeBalayage() {
        #expect(ReglesBalayage.raisonEchec(pour: .allume) == nil)
    }

    @Test(arguments: [-127, -60, 0])
    func rssiDansLesBornesEstValide(rssi: Int) {
        #expect(ReglesBalayage.rssiValide(rssi))
    }

    /// 127 est la valeur renvoyée par iOS quand le RSSI est indisponible.
    @Test(arguments: [127, 1, -128, Int.min, Int.max])
    func rssiHorsBornesEstInvalide(rssi: Int) {
        #expect(!ReglesBalayage.rssiValide(rssi))
    }

    @Test func nomNormalInchange() {
        #expect(ReglesBalayage.nettoyerNom("Casque fictif") == "Casque fictif")
    }

    @Test func nomAvecCaracteresDeControleEstNettoye() {
        #expect(ReglesBalayage.nettoyerNom("Faux\nnom\u{0000}") == "Fauxnom")
    }

    @Test func nomTropLongEstCoupe() {
        let long = String(repeating: "a", count: 500)
        #expect(ReglesBalayage.nettoyerNom(long)?.count == ReglesBalayage.longueurNomMaximale)
    }

    @Test(arguments: [nil, "", "   ", "\n\t"] as [String?])
    func nomVideOuAbsentDevientNil(nom: String?) {
        #expect(ReglesBalayage.nettoyerNom(nom) == nil)
    }
}
