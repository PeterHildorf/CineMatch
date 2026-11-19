//
//  MockPreferencesService.swift
//  CineMatch
//

/// Indstillinger i hukommelsen til previews og tests.
final class MockPreferencesService: PreferencesService {
    var stored: StreamingPreferences?
    /// Sæt i tests for at simulere, at der ikke kan gemmes.
    var saveError: Error?
    private(set) var saveCallCount = 0

    // nonisolated: så den kan bruges som standardværdi i andre init (de køres uden for main actor).
    nonisolated init(stored: StreamingPreferences? = nil) {
        self.stored = stored
    }

    func streamingPreferences() async throws -> StreamingPreferences? {
        stored
    }

    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        stored = preferences
    }

    func deleteStreamingPreferences() async throws {
        stored = nil
    }
}
