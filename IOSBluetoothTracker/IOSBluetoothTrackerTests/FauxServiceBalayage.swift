//
//  FauxServiceBalayage.swift
//  IOSBluetoothTracker
//
//  Created by Guest User on 24/11/2026.
//

@testable import IOSBluetoothTracker

struct FauxServiceBalayage: ServiceBalayage {
    var appareils: [AppareilDetecte] = []
    var erreur: ErreurBalayage?

    func balayer(duree: Duration) async throws -> [AppareilDetecte] {
        if let erreur { throw erreur }
        return appareils
    }
}
