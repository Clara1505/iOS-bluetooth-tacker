//
//  EtatBluetooth.swift
//  IOSBluetoothTracker
//

/// État du Bluetooth de l'iPhone, traduit depuis `CBManagerState`
/// pour que les règles restent testables sans CoreBluetooth.
enum EtatBluetooth: Equatable, Sendable {
    case inconnu, allume, eteint, nonAutorise, nonSupporte
}
