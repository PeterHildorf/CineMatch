//
//  MockTasteSignalService.swift
//  CineMatch
//

/// Gemmer likes/dislikes i hukommelsen. Bruges i tests, previews og indtil Supabase-versionen findes.
final class MockTasteSignalService: TasteSignalService {
    /// Nyeste først.
    private(set) var signals: [TasteSignal]
    /// Sæt en fejl i tests for at simulere, at Supabase ikke svarer.
    var errorToThrow: TasteSignalServiceError?
    private(set) var saveCallCount = 0

    init(signals: [TasteSignal] = [], errorToThrow: TasteSignalServiceError? = nil) {
        self.signals = signals
        self.errorToThrow = errorToThrow
    }

    /// Hurtigt opslag i tests.
    var kindByMovieID: [Int: TasteSignal.Kind] {
        Dictionary(signals.map { ($0.movieID, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    func allSignals() async throws -> [TasteSignal] {
        if let errorToThrow { throw errorToThrow }
        return signals
    }

    func save(_ signal: TasteSignal) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        signals.removeAll { $0.movieID == signal.movieID }
        signals.insert(signal, at: 0)
    }

    func deleteSignal(movieID: Int) async throws {
        if let errorToThrow { throw errorToThrow }
        signals.removeAll { $0.movieID == movieID }
    }
}
