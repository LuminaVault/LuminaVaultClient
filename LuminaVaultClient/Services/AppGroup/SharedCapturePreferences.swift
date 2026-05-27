// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedCapturePreferences.swift
//
// Small App Group UserDefaults bridge for values the share extension and
// host app both need. Keep it Foundation-only so it can compile into the
// extension target.

import Foundation

enum SharedCapturePreferences {
    private static let lastShareSpaceIDKey = "lv.share.lastSpaceID"

    static var lastShareSpaceID: UUID? {
        get {
            guard let raw = defaults?.string(forKey: lastShareSpaceIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            guard let defaults else { return }
            if let newValue {
                defaults.set(newValue.uuidString, forKey: lastShareSpaceIDKey)
            } else {
                defaults.removeObject(forKey: lastShareSpaceIDKey)
            }
        }
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedAppGroup.identifier)
    }
}
