//
//  MockRecommendationService.swift
//  CineMatch
//

/// Falske anbefalinger, så UI'et kan bygges og testes, før ML-servicen kører.
final class MockRecommendationService: RecommendationService {
    /// Det, "ML-servicen" skriver ved næste `requestRecompute()`.
    static let sampleRecommendations: [Recommendation] = [
        Recommendation(rank: 1, movieID: 2571, score: 0.94, reason: "Because you liked Inception · Director: Christopher Nolan"),
        Recommendation(rank: 2, movieID: 318, score: 0.91, reason: "Because you liked The Green Mile · Themes: prison, friendship"),
        Recommendation(rank: 3, movieID: 1265, score: 0.87, reason: "Because you liked Palm Springs · Themes: time loop"),
        Recommendation(rank: 4, movieID: 1, score: 0.82, reason: "Because you liked Finding Nemo · Studio: Pixar"),
        Recommendation(rank: 5, movieID: 1258, score: 0.78, reason: "Because you liked Alien · Themes: isolation, horror"),
    ]

    /// Det, der "ligger i tabellen" lige nu. Tom = brugeren har ikke fået anbefalinger endnu.
    private(set) var stored: [Recommendation]
    /// Nyt batch ved hvert `requestRecompute()`, så tests kan se, at målinger skifter batch.
    private(set) var batch: RecommendationBatch?
    private let nextResult: [Recommendation]
    /// Hvor længe et "Beregn nu" tager – så man kan se loading-tilstanden i appen.
    private let delay: Duration
    /// Hvis sat: film, brugeren har set, fjernes fra næste resultat – ligesom de rigtige modeller.
    private let tasteSignalService: (any TasteSignalService)?

    /// Sæt fejl i tests for at simulere de forskellige svar fra ML-servicen.
    var recomputeError: RecommendationServiceError?
    var loadError: RecommendationServiceError?

    private(set) var recomputeCallCount = 0

    init(
        stored: [Recommendation] = [],
        nextResult: [Recommendation] = sampleRecommendations,
        delay: Duration = .zero,
        tasteSignalService: (any TasteSignalService)? = nil
    ) {
        self.tasteSignalService = tasteSignalService
        self.stored = stored
        self.batch = stored.isEmpty ? nil : RecommendationBatch(modelVersion: "mock", inputCount: TasteInput.minimumCount)
        self.nextResult = nextResult
        self.delay = delay
    }

    func requestRecompute() async throws {
        recomputeCallCount += 1
        try await Task.sleep(for: delay)
        if let recomputeError { throw recomputeError }
        let seen = (try? await tasteSignalService?.allSignals())?.seenMovieIDs ?? []
        stored = nextResult.filter { !seen.contains($0.movieID) }
        batch = RecommendationBatch(modelVersion: "mock", inputCount: TasteInput.minimumCount)
    }

    func latestRecommendations() async throws -> [Recommendation] {
        if let loadError { throw loadError }
        return stored.sorted { $0.rank < $1.rank }
    }

    func latestBatch() async -> RecommendationBatch? {
        batch
    }

    func clearRecommendations() async {
        stored = []
        batch = nil
    }
}
