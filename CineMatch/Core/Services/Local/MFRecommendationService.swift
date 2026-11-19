//
//  MFRecommendationService.swift
//  CineMatch
//

/// Anbefalinger fra Mikkels model, regnet lokalt ud fra brugerens domme.
///
/// - Input er alle sete film med deres tal fra skalaen: Horrible 1 · Bad 2 · Neutral 3 · Great 4 · Fantastic 5.
/// - "Haven't seen" (0) er ikke input og udelukker ikke filmen fra anbefalingerne.
/// - Alle sete film anbefales aldrig.
/// - Modellen giver ingen forklaring, så begrundelsen er bare "Based on your ratings".
final class MFRecommendationService: RecommendationService {
    static let reasonText = "Based on your ratings"

    private let store: MFModelStore
    private let tasteSignalService: any TasteSignalService
    /// Appen viser 5, men skal kunne filtrere (fx "Only my services").
    private let candidateCount: Int
    private var latest: [Recommendation] = []
    private var batch: RecommendationBatch?

    init(store: MFModelStore, tasteSignalService: any TasteSignalService, candidateCount: Int = 50) {
        self.store = store
        self.tasteSignalService = tasteSignalService
        self.candidateCount = candidateCount
    }

    func requestRecompute() async throws {
        let signals: [TasteSignal]
        do {
            signals = try await tasteSignalService.allSignals()
        } catch {
            throw RecommendationServiceError.network
        }

        // Én dom pr. film (den nyeste). Skalaens tal (1–5) ligger inden for modellens ½–5.
        var seen = Set<Int>()
        let ratings = signals.compactMap { signal -> MatrixFactorizationRecommender.Rating? in
            guard signal.verdict.isSeen, seen.insert(signal.movieID).inserted else { return nil }
            return MatrixFactorizationRecommender.Rating(tmdbId: signal.movieID, stars: Double(signal.score))
        }
        guard ratings.count >= TasteInput.minimumCount else {
            throw RecommendationServiceError.tooFewRatings
        }

        let recommender: MatrixFactorizationRecommender
        do {
            recommender = try await store.recommender()
        } catch {
            throw RecommendationServiceError.notReady
        }

        let output: MatrixFactorizationRecommender.Output
        do {
            output = try recommender.recommend(
                ratings: ratings,
                excluding: signals.seenMovieIDs,
                limit: candidateCount
            )
        } catch {
            throw RecommendationServiceError.unknown
        }
        // Ratede film, der ikke findes i modellen, tæller ikke.
        guard output.ratingsUsed >= TasteInput.minimumCount else {
            throw RecommendationServiceError.tooFewRatings
        }

        latest = output.results.enumerated().map { position, result in
            Recommendation(
                rank: position + 1,
                movieID: result.tmdbId,
                score: result.score,      // rå rangeringsværdi – vises ikke som procent
                reason: Self.reasonText
            )
        }
        batch = RecommendationBatch(modelVersion: recommender.modelVersion, inputCount: output.ratingsUsed)
    }

    func latestRecommendations() async throws -> [Recommendation] {
        latest
    }

    func latestBatch() async -> RecommendationBatch? {
        batch
    }

    func clearRecommendations() async {
        latest = []
        batch = nil
    }
}
