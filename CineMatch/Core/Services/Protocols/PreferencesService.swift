//
//  PreferencesService.swift
//  CineMatch
//

/// Gemmer brugerens indstillinger, fx streamingtjenester.
/// I dag lokalt på telefonen. Senere i Supabase (`preferences`, se migration 0003).
protocol PreferencesService: Sendable {
    /// `nil` = brugeren har aldrig valgt tjenester (så vises valget efter login).
    func streamingPreferences() async throws -> StreamingPreferences?
    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws
}
