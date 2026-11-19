//
//  PreferencesService.swift
//  CineMatch
//

/// Gemmer brugerens indstillinger, fx streamingtjenester.
/// I Supabase (`preferences`, se migration 0003) – lokalt på telefonen, hvis Supabase ikke er sat op.
protocol PreferencesService: Sendable {
    /// `nil` = brugeren har aldrig valgt tjenester (så vises valget efter login).
    func streamingPreferences() async throws -> StreamingPreferences?
    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws
    /// Glemmer valget, så brugeren bliver spurgt igen (bruges af `-freshUser`).
    func deleteStreamingPreferences() async throws
}
