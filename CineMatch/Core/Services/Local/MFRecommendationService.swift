//
//  MFRecommendationService.swift
//  CineMatch
//

/// Anbefalinger fra Mikkels model, regnet lokalt ud fra brugerens stjerner.
///
/// - Kun svar med stjerner er input. Likes uden stjerner oversættes ikke til stjerner (ingen valideret regel).
/// - Alle film, brugeren har svaret på (også likes, dislikes og neutrale), anbefales aldrig.
/// - Modellen giver ingen forklaring, så begrundelsen er bare "Based on your star ratings".
final class MFRecommendationService: RecommendationService {
    static let reasonText = "Based on your star ratings"

    private let store: MFModelStore
    private let tasteSignalService: any TasteSignalService
    /// Appen viser 5, men skal kunne filtrere (fx "Only my services").
    private let candidateCount: Int
    private var latest: [Recommendation] = []

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

        // Én rating pr. film (den nyeste).
        var seen = Set<Int>()
        let ratings = signals.compactMap { signal -> MatrixFactorizationRecommender.Rating? in
            guard let stars = signal.rating, seen.insert(signal.movieID).inserted else { return nil }
            return MatrixFactorizationRecommender.Rating(tmdbId: signal.movieID, stars: stars)
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
                excluding: Set(signals.map(\.movieID)),
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
    }

    func latestRecommendations() async throws -> [Recommendation] {
        latest
    }
}
