//
//  MatrixFactorizationTests.swift
//  CineMatchTests
//

import CryptoKit
import Foundation
import Testing
@testable import CineMatch

/// Testbundlen, hvor `mf_reference_cases.json` ligger.
private final class TestBundleMarker {}

/// Mikkels model skal give præcis det samme som Python (`mf_reference_cases.json`).
struct MFReferenceTests {

    private struct ReferenceFile: Decodable {
        struct Case: Decodable {
            struct Input: Decodable {
                struct Rating: Decodable { let tmdbId: Int; let rating: Double }
                let ratings: [Rating]
                let excludeTmdbIds: [Int]
                let k: Int
            }
            struct Expected: Decodable {
                struct Item: Decodable { let tmdbId: Int; let score: Double }
                let personalized: Bool
                let ratingsUsed: Int
                let recommendations: [Item]
            }
            let name: String
            let input: Input
            let expected: Expected
        }
        let format: String
        let schemaVersion: Int
        let modelVersion: String
        let scoreTolerance: Double
        let modelJsonSha256: String
        let cases: [Case]
    }

    private var appBundle: Bundle { Bundle(for: MockAuthService.self) }
    private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

    private func loadModelData() throws -> Data {
        let url = try #require(appBundle.url(forResource: MFModelStore.fileName, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func loadReference() throws -> ReferenceFile {
        let url = try #require(testBundle.url(forResource: "mf_reference_cases", withExtension: "json"))
        return try JSONDecoder().decode(ReferenceFile.self, from: Data(contentsOf: url))
    }

    @Test func referenceFileMatchesBundledModel() throws {
        let reference = try loadReference()
        let data = try loadModelData()
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(reference.format == "cinematch.mf-reference-cases")
        #expect(reference.schemaVersion == 1)
        #expect(sha == reference.modelJsonSha256, "cinematch_mf.json er ikke den fil, referencerne er lavet med")
        let recommender = try MatrixFactorizationRecommender(file: JSONDecoder().decode(MFModelFile.self, from: data))
        #expect(recommender.modelVersion == reference.modelVersion)
        #expect(recommender.movieCount == 9014)
    }

    @Test func swiftGivesSameResultsAsPython() throws {
        let reference = try loadReference()
        let recommender = try MatrixFactorizationRecommender(
            file: JSONDecoder().decode(MFModelFile.self, from: loadModelData())
        )

        for testCase in reference.cases {
            let output = try recommender.recommend(
                ratings: testCase.input.ratings.map { .init(tmdbId: $0.tmdbId, stars: $0.rating) },
                excluding: Set(testCase.input.excludeTmdbIds),
                limit: testCase.input.k
            )
            let expected = testCase.expected

            #expect(output.personalized == expected.personalized, "\(testCase.name)")
            #expect(output.ratingsUsed == expected.ratingsUsed, "\(testCase.name)")
            #expect(output.results.map(\.tmdbId) == expected.recommendations.map(\.tmdbId), "\(testCase.name): rækkefølge")
            for (got, want) in zip(output.results, expected.recommendations) {
                #expect(abs(got.score - want.score) <= reference.scoreTolerance, "\(testCase.name): \(got.tmdbId)")
            }
        }
    }
}

/// Små, håndregnede tests af modellen og titler.
struct MatrixFactorizationRecommenderTests {

    /// 3 film, 1 faktor. Film 2 ligner film 1 (samme fortegn), film 3 er det modsatte.
    private func makeRecommender() throws -> MatrixFactorizationRecommender {
        let json = """
        { "format": "cinematch.matrix-factorization", "schemaVersion": 1,
          "modelType": "explicit_rating_matrix_factorization", "modelVersion": "test",
          "factorCount": 1, "globalMean": 3.0, "foldInRegularization": 1.0, "biasRegularization": 5.0,
          "movies": [
            { "tmdbId": 1, "movieLensId": 1, "title": "One (2000)", "genres": [], "bias": 0.0, "factors": [1.0] },
            { "tmdbId": 2, "movieLensId": 2, "title": "Two (2001)", "genres": [], "bias": 0.0, "factors": [0.9] },
            { "tmdbId": 3, "movieLensId": 3, "title": "Three (2002)", "genres": [], "bias": 0.0, "factors": [-1.0] }
          ] }
        """
        return try MatrixFactorizationRecommender(file: JSONDecoder().decode(MFModelFile.self, from: Data(json.utf8)))
    }

    @Test func likingAMovieRanksSimilarMoviesFirstAndExcludesRated() throws {
        let output = try makeRecommender().recommend(ratings: [.init(tmdbId: 1, stars: 5)], limit: 5)

        #expect(output.results.map(\.tmdbId) == [2, 3])
        #expect(output.personalized)
    }

    @Test func excludedAndUnknownIDsAreHandled() throws {
        let output = try makeRecommender().recommend(
            ratings: [.init(tmdbId: 1, stars: 5), .init(tmdbId: 99, stars: 4)],
            excluding: [2, 12345],
            limit: 5
        )

        #expect(output.results.map(\.tmdbId) == [3])
        #expect(output.ratingsUsed == 1)
        #expect(output.unknownRatedIDs == [99])
    }

    @Test func invalidInputIsRejected() throws {
        let recommender = try makeRecommender()

        #expect(throws: MatrixFactorizationRecommender.InputError.invalidRating(4.3)) {
            try recommender.recommend(ratings: [.init(tmdbId: 1, stars: 4.3)], limit: 5)
        }
        #expect(throws: MatrixFactorizationRecommender.InputError.duplicateRating(1)) {
            try recommender.recommend(ratings: [.init(tmdbId: 1, stars: 4), .init(tmdbId: 1, stars: 5)], limit: 5)
        }
        #expect(throws: MatrixFactorizationRecommender.InputError.invalidLimit) {
            try recommender.recommend(ratings: [], limit: 0)
        }
    }

    @Test func solverSolvesSmallSystem() {
        // 2x + y = 5, x + 3y = 10  →  x = 1, y = 3
        let x = MatrixFactorizationRecommender.solve([[2, 1], [1, 3]], [5, 10])
        #expect(abs(x[0] - 1) < 1e-12 && abs(x[1] - 3) < 1e-12)
    }

    @Test(arguments: [
        ("Matrix, The (1999)", "The Matrix", 1999),
        ("Seven (a.k.a. Se7en) (1995)", "Seven", 1995),
        ("Toy Story (1995)", "Toy Story", 1995),
        ("Grand Budapest Hotel, The (2014)", "The Grand Budapest Hotel", 2014),
        ("Moonlight", "Moonlight", 0),
    ])
    func movieLensTitlesAreCleanedUp(raw: String, title: String, year: Int) {
        let parsed = MFTitleParser.parse(raw)
        #expect(parsed.title == title)
        #expect((parsed.year ?? 0) == year)
    }
}

@MainActor
struct MFServiceTests {

    private var appBundle: Bundle { Bundle(for: MockAuthService.self) }

    private func ratings(_ ids: [Int], stars: Double = 4.5) -> [TasteSignal] {
        ids.map { TasteSignal(movieID: $0, kind: TasteSignal.kind(forStars: stars), rating: stars) }
    }

    @Test func tooFewRatingsThrows() async {
        // 4 ratings + mange likes uden stjerner: likes tæller ikke for Mikkels model.
        let signals = MockTasteSignalService(signals: ratings([862, 8844, 15602, 31357])
            + [278, 680, 550].map { TasteSignal(movieID: $0, kind: .like) })
        let service = MFRecommendationService(store: MFModelStore(bundle: appBundle), tasteSignalService: signals)

        await #expect(throws: RecommendationServiceError.tooFewRatings) {
            try await service.requestRecompute()
        }
    }

    @Test func recommendsUnansweredMoviesWithReason() async throws {
        // Samme ratings som referencecasen "mixed_ratings", hvor top 3 er 238, 240, 278.
        let mixed: [(Int, Double)] = [(862, 5), (8844, 1), (15602, 4.5), (31357, 2), (11862, 3.5)]
        let rated = mixed.map { $0.0 }
        let liked = [238, 278]   // skal udelukkes, fordi de er besvaret (likes uden stjerner)
        let signals = MockTasteSignalService(
            signals: mixed.map { TasteSignal(movieID: $0.0, kind: TasteSignal.kind(forStars: $0.1), rating: $0.1) }
                + liked.map { TasteSignal(movieID: $0, kind: .like) }
        )
        let service = MFRecommendationService(store: MFModelStore(bundle: appBundle), tasteSignalService: signals)

        try await service.requestRecompute()
        let recommendations = try await service.latestRecommendations()

        #expect(recommendations.count == 50)
        #expect(recommendations.map(\.rank) == Array(1...50))
        #expect(Set(recommendations.map(\.movieID)).isDisjoint(with: rated + liked))
        #expect(recommendations[0].movieID == 240, "The Godfather Part II er nr. 1, når 238 og 278 er udelukket")
        #expect(recommendations[0].reason == MFRecommendationService.reasonText)
    }

    @Test func movieDataUsesTMDBIdsAndOnboardingStarters() async throws {
        let service = MFMovieDataService(store: MFModelStore(bundle: appBundle), starters: MockMovieDataService())

        let starters = try await service.allTitles()
        let looked = try await service.titles(withIDs: [603, 999_999_999])

        #expect(starters.map(\.id) == [278, 603, 862, 137, 694], "Startfilmene får TMDB-id som film-id")
        #expect(looked.map(\.title) == ["The Matrix"])
        #expect(looked.first?.year == 1999)
    }
}

@MainActor
struct StarRatingTasteTests {

    @Test func starsAreSavedWithDerivedKind() async {
        let signals = MockTasteSignalService()
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: signals,
            input: .starRatings
        )
        await viewModel.load()

        await viewModel.rate(4.5)   // Shawshank → like
        await viewModel.rate(3.0)   // The Matrix → neutral
        await viewModel.rate(1.5)   // Toy Story → dislike

        #expect(signals.signals.map(\.rating) == [1.5, 3.0, 4.5])
        #expect(signals.kindByMovieID == [318: .like, 2571: .neutral, 1: .dislike])
        #expect(viewModel.ratedCount == 3)
        #expect(viewModel.progressCount == 3)
        #expect(viewModel.likeCount == 1)
    }

    @Test func likesWithoutStarsDoNotCountForStarModel() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: MockTasteSignalService(),
            input: .starRatings
        )
        await viewModel.load()

        await viewModel.like()

        #expect(viewModel.likeCount == 1)
        #expect(viewModel.progressCount == 0)
    }

    @Test func undoRemovesRating() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: MockTasteSignalService(),
            input: .starRatings
        )
        await viewModel.load()

        await viewModel.rate(5)
        await viewModel.undo()

        #expect(viewModel.ratedCount == 0)
        #expect(viewModel.current?.id == 318)
    }
}
