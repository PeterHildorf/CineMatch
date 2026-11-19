//
//  LocalPreferencesService.swift
//  CineMatch
//

import Foundation

/// Gemmer indstillinger i `UserDefaults`, så de overlever, at appen lukkes.
/// Én nøgle pr. bruger, så en ny bruger på samme telefon altid bliver spurgt om sine tjenester.
/// Bruges kun, hvis Supabase ikke er sat op (ellers `SupabasePreferencesService`).
final class LocalPreferencesService: PreferencesService {
    /// Alle nøgler starter sådan (bruges af `-freshUser` til at rydde op).
    static let keyPrefix = "streamingPreferences"

    private let defaults: UserDefaults
    private let key: String

    init(userID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "\(Self.keyPrefix).\(userID)"
    }

    func streamingPreferences() async throws -> StreamingPreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(StreamingPreferences.self, from: data)
    }

    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }

    func deleteStreamingPreferences() async throws {
        defaults.removeObject(forKey: key)
    }
}
