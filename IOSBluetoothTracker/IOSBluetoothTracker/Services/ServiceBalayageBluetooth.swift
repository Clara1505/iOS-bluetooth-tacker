//
//  ServiceBalayageBluetooth.swift
//  IOSBluetoothTracker
//

import CoreBluetooth
import Foundation

/// Vrai service de balayage, basé sur CoreBluetooth.
///
/// Le gestionnaire est créé avec la file `nil` : CoreBluetooth appelle donc le délégué
/// sur le thread principal, ce qui permet `MainActor.assumeIsolated` plus bas.
@MainActor
final class ServiceBalayageBluetooth: NSObject, ServiceBalayage {
    private var gestionnaire: CBCentralManager?
    private var attenteEtat: CheckedContinuation<EtatBluetooth, Never>?
    private var collecteur = CollecteurAppareils()
    private var enCours = false
    private var interrompu = false

    /// Lance un balayage BLE de `duree` secondes. La permission est demandée au premier appel
    /// (création du gestionnaire), donc au moment du besoin.
    /// - Parameter duree: durée du balayage, en secondes.
    /// - Returns: `.controleImpossible` si le Bluetooth est coupé, refusé, non supporté,
    ///   coupé pendant le balayage, ou si un balayage est déjà en cours. Jamais une liste vide dans ces cas (D4).
    func lancerBalayage(duree: TimeInterval) async -> ResultatBalayage {
        guard !enCours else { return .controleImpossible(.interrompu) }
        enCours = true
        defer { enCours = false }

        let etat = await attendreEtatConnu()
        if let raison = ReglesBalayage.raisonEchec(pour: etat) {
            return .controleImpossible(raison)
        }
        guard let gestionnaire else { return .controleImpossible(.interrompu) }

        collecteur.vider()
        interrompu = false
        // Services `nil` : on veut voir tous les appareils, pas seulement un type connu.
        gestionnaire.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        do {
            try await Task.sleep(for: .seconds(duree))
        } catch {
            // Tâche annulée : le balayage n'est pas complet (D4).
            gestionnaire.stopScan()
            return .controleImpossible(.interrompu)
        }
        gestionnaire.stopScan()

        if interrompu { return .controleImpossible(.interrompu) }
        return .complet(collecteur.appareils, plafondAtteint: collecteur.plafondAtteint)
    }

    /// Crée le gestionnaire au premier besoin (ce qui affiche la demande de permission)
    /// et attend que l'état du Bluetooth soit connu.
    /// - Returns: l'état connu du Bluetooth.
    private func attendreEtatConnu() async -> EtatBluetooth {
        if let gestionnaire, let etat = Self.convertir(gestionnaire.state) {
            return etat
        }
        return await withCheckedContinuation { continuation in
            attenteEtat = continuation
            if gestionnaire == nil {
                gestionnaire = CBCentralManager(delegate: self, queue: nil)
            }
        }
    }

    /// Traduit l'état CoreBluetooth.
    /// - Parameter etat: état fourni par CoreBluetooth.
    /// - Returns: l'état traduit, ou `nil` si l'état n'est pas encore connu (il faut attendre).
    private static func convertir(_ etat: CBManagerState) -> EtatBluetooth? {
        switch etat {
        case .poweredOn: return .allume
        case .poweredOff: return .eteint
        case .unauthorized: return .nonAutorise
        case .unsupported: return .nonSupporte
        case .unknown, .resetting: return nil
        @unknown default: return .inconnu
        }
    }
}

extension ServiceBalayageBluetooth: CBCentralManagerDelegate {
    /// Appelé par CoreBluetooth quand l'état du Bluetooth change.
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let etat = central.state
        MainActor.assumeIsolated {
            // Tout état autre que « allumé » (y compris une réinitialisation) arrête le balayage :
            // un balayage en cours ne peut plus être déclaré complet (D4).
            if etat != .poweredOn { interrompu = true }
            guard let converti = Self.convertir(etat) else { return }
            attenteEtat?.resume(returning: converti)
            attenteEtat = nil
        }
    }

    /// Appelé par CoreBluetooth à chaque annonce reçue pendant le balayage.
    /// Les données reçues sont externes : le nom est nettoyé et le RSSI validé dans le collecteur (T5).
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let identifiant = peripheral.identifier
        let nom = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let valeurRssi = RSSI.intValue
        MainActor.assumeIsolated {
            collecteur.enregistrer(identifiant: identifiant, nom: nom, rssi: valeurRssi, date: .now)
        }
    }
}
