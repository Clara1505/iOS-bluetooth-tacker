//
//  CollecteurAppareilsTests.swift
//  IOSBluetoothTrackerTests
//

import Foundation
import Testing
@testable import IOSBluetoothTracker

/// Tests de la déduplication et du plafond de sécurité (D1), avec des identifiants fictifs.
@MainActor
struct CollecteurAppareilsTests {
    private let debut = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Déduplication

    @Test func memeIdentifiantDonneUnSeulAppareil() {
        var collecteur = CollecteurAppareils()
        let id = UUID()
        for i in 0..<50 {
            collecteur.enregistrer(identifiant: id, nom: "Fictif", rssi: -60, date: debut + Double(i))
        }
        #expect(collecteur.appareils.count == 1)
    }

    @Test func gardeLaPremiereDateEtMetAJourLaDerniere() throws {
        var collecteur = CollecteurAppareils()
        let id = UUID()
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -60, date: debut)
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -55, date: debut + 10)
        let appareil = try #require(collecteur.appareils.first)
        #expect(appareil.premiereDetection == debut)
        #expect(appareil.derniereDetection == debut + 10)
        #expect(appareil.rssi == -55)
    }

    @Test func unNomAbsentGardeLeNomPrecedent() throws {
        var collecteur = CollecteurAppareils()
        let id = UUID()
        collecteur.enregistrer(identifiant: id, nom: "Fictif", rssi: -60, date: debut)
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -60, date: debut + 1)
        #expect(try #require(collecteur.appareils.first).nomAnnonce == "Fictif")
    }

    @Test func leNomEstNettoye() throws {
        var collecteur = CollecteurAppareils()
        collecteur.enregistrer(identifiant: UUID(), nom: "Fic\ntif", rssi: -60, date: debut)
        #expect(try #require(collecteur.appareils.first).nomAnnonce == "Fictif")
    }

    @Test func unRssiInvalideGardeLaValeurPrecedente() throws {
        var collecteur = CollecteurAppareils()
        let id = UUID()
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -70, date: debut)
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: 127, date: debut + 1)
        #expect(try #require(collecteur.appareils.first).rssi == -70)
    }

    @Test func unRssiInvalideALaPremiereDetectionDonneLeMinimum() throws {
        var collecteur = CollecteurAppareils()
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: 127, date: debut)
        #expect(try #require(collecteur.appareils.first).rssi == ReglesBalayage.rssiMinimum)
    }

    @Test func lesAppareilsSontTriesDuPlusFortAuPlusFaible() {
        var collecteur = CollecteurAppareils()
        for rssi in [-90, -40, -70] {
            collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: rssi, date: debut)
        }
        #expect(collecteur.appareils.map(\.rssi) == [-40, -70, -90])
    }

    @Test func viderRemetToutAZero() {
        var collecteur = CollecteurAppareils(plafond: 1)
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: -60, date: debut)
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: -50, date: debut)
        collecteur.vider()
        #expect(collecteur.appareils.isEmpty)
        #expect(collecteur.plafondAtteint == false)
    }

    // MARK: - Plafond de sécurité (D1)

    /// Inondation : 10 000 identifiants différents, la liste ne dépasse jamais le plafond.
    @Test func inondationDAnnoncesLimiteeAuPlafond() {
        var collecteur = CollecteurAppareils()
        for i in 0..<10_000 {
            collecteur.enregistrer(identifiant: UUID(), nom: "Faux \(i)", rssi: -50 - (i % 77), date: debut)
        }
        #expect(collecteur.appareils.count == ReglesBalayage.plafondAppareils)
        #expect(collecteur.plafondAtteint)
    }

    @Test func sousLePlafondRienNEstSignale() {
        var collecteur = CollecteurAppareils(plafond: 3)
        for _ in 0..<3 {
            collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: -60, date: debut)
        }
        #expect(collecteur.appareils.count == 3)
        #expect(collecteur.plafondAtteint == false)
    }

    /// Un traceur proche (signal fort) arrivé après une inondation lointaine reste dans la liste.
    @Test func unSignalFortRemplaceLePlusFaible() {
        var collecteur = CollecteurAppareils(plafond: 3)
        for rssi in [-90, -85, -80] {
            collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: rssi, date: debut)
        }
        let traceur = UUID()
        collecteur.enregistrer(identifiant: traceur, nom: nil, rssi: -40, date: debut)
        #expect(collecteur.appareils.map(\.rssi) == [-40, -80, -85])
        #expect(collecteur.appareils.first?.identifiantSysteme == traceur)
        #expect(collecteur.plafondAtteint)
    }

    /// Un signal plus faible (ou égal) que tous ceux de la liste pleine est ignoré.
    @Test(arguments: [-95, -90])
    func unSignalFaibleEstIgnoreQuandLaListeEstPleine(rssi: Int) {
        var collecteur = CollecteurAppareils(plafond: 2)
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: -90, date: debut)
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: -60, date: debut)
        collecteur.enregistrer(identifiant: UUID(), nom: nil, rssi: rssi, date: debut)
        #expect(collecteur.appareils.map(\.rssi) == [-60, -90])
        #expect(collecteur.plafondAtteint)
    }

    /// Un appareil déjà présent continue d'être mis à jour quand la liste est pleine.
    @Test func unAppareilConnuEstMisAJourMemeListePleine() throws {
        var collecteur = CollecteurAppareils(plafond: 1)
        let id = UUID()
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -60, date: debut)
        collecteur.enregistrer(identifiant: id, nom: nil, rssi: -50, date: debut + 5)
        let appareil = try #require(collecteur.appareils.first)
        #expect(appareil.rssi == -50)
        #expect(collecteur.plafondAtteint == false)
    }

    @Test(arguments: [0, -5])
    func unPlafondInvalideEstRameneAUn(plafond: Int) {
        #expect(CollecteurAppareils(plafond: plafond).plafond == 1)
    }
}
