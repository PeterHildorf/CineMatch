//
//  LocalPreferencesService.swift
//  CineMatch
//

import Foundation

/// Gemmer indstillinger i `UserDefaults`, så de overlever, at appen lukkes.
/// Midlertidig: følger telefonen, ikke brugeren. Erstattes af en Supabase-version.
final class LocalPreferencesService: PreferencesService {
    private let defaults: UserDefaults
    private let key = "streamingPreferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func streamingPreferences() async throws -> StreamingPreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(StreamingPreferences.self, from: data)
    }

    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
