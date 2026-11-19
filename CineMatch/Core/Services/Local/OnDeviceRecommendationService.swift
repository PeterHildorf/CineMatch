//
//  OnDeviceRecommendationService.swift
//  CineMatch
//

/// Laver anbefalinger lokalt med Antons model (ingen server).
/// Input: film bedømt Great eller Fantastic (Fantastic forrest). Alle sete film anbefales aldrig,
/// men "Haven't seen" gør ikke – dem har brugeren jo ikke set.
/// TODO: Når Antons nye model tager hele skalaen (0–5), sendes `signal.score` med i stedet.
final class OnDeviceRecommendationService: RecommendationService {
    private let store: ModelStore
    private let tasteSignalService: any TasteSignalService
    private var latest: [Recommendation] = []
    private var batch: RecommendationBatch?
    /// Så mange kandidater gemmes. Appen viser 5, men skal kunne filtrere (fx "Only my services").
    /// Med 25 naboer pr. film giver få likes færre kandidater end dette – det er i orden.
    private let candidateCount: Int

    init(store: ModelStore, tasteSignalService: any TasteSignalService, candidateCount: Int = 50) {
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

        // Fantastic først, derefter nyeste, så de stærkeste kommer med, hvis brugeren har flere end modellen bruger (25).
        let liked = signals.likedMovieIDs
        guard liked.count >= TasteViewModel.minimumLikes else {
            throw RecommendationServiceError.tooFewLikes
        }

        let recommender: OnDeviceRecommender
        do {
            recommender = try await store.recommender()
        } catch {
            throw RecommendationServiceError.notReady
        }

        let results = recommender.recommend(liked: liked, excluding: signals.seenMovieIDs, limit: candidateCount)
        latest = results.enumerated().map { position, result in
            Recommendation(
                rank: position + 1,
                movieID: result.movieID,
                score: result.score,
                reason: recommender.reason(for: result)
            )
        }
        // Modellen bruger højst `maxLiked` likes, men det er antallet, brugeren har givet, der er interessant.
        batch = RecommendationBatch(modelVersion: recommender.modelVersion, inputCount: liked.count)
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
