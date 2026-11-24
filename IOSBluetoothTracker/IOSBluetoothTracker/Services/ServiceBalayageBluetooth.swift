import CoreBluetooth
import Foundation

@MainActor
final class ServiceBalayageBluetooth: NSObject, ServiceBalayage {
    private var gestionnaire: CBCentralManager?
    private var attenteEtat: CheckedContinuation<EtatBluetooth, Never>?
    private var collecteur = CollecteurAppareils()
    private var enCours = false
    private var interrompu = false

    /// Lance un balayage BLE de `duree` secondes. La permission est demandée au premier appel.
    /// - Returns: `.controleImpossible` si le Bluetooth est coupé, refusé, non supporté
    ///   ou coupé pendant le balayage. Jamais une liste vide dans ces cas (D4).
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
        gestionnaire.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        do {
            try await Task.sleep(for: .seconds(duree))
        } catch {
            gestionnaire.stopScan()
            return .controleImpossible(.interrompu)
        }
        gestionnaire.stopScan()

        if interrompu { return .controleImpossible(.interrompu) }
        return .complet(collecteur.appareils)
    }

    /// Crée le gestionnaire au premier besoin (ce qui affiche la demande de permission)
    /// et attend que l'état du Bluetooth soit connu.
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

    /// Traduit l'état CoreBluetooth ; `nil` signifie « pas encore connu, attendre ».
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
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let etat = central.state
        MainActor.assumeIsolated {
            guard let converti = Self.convertir(etat) else { return }
            if converti != .allume { interrompu = true }
            attenteEtat?.resume(returning: converti)
            attenteEtat = nil
        }
    }

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