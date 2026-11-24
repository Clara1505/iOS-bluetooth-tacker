import Foundation

enum ReglesBalayage {
    static let dureeParDefaut: TimeInterval = 30
    static let rssiMinimum = -127

    /// Raison pour laquelle le contrôle est impossible, ou `nil` si le balayage peut démarrer (D4).
    static func raisonEchec(pour etat: EtatBluetooth) -> RaisonEchec? {
        switch etat {
        case .allume: return nil
        case .eteint: return .bluetoothCoupe
        case .nonAutorise: return .permissionRefusee
        case .nonSupporte: return .nonSupporte
        case .inconnu: return .interrompu
        }
    }

    /// Indique si une valeur RSSI est exploitable (iOS renvoie 127 quand elle est indisponible).
    static func rssiValide(_ rssi: Int) -> Bool {
        (rssiMinimum...0).contains(rssi)
    }
}