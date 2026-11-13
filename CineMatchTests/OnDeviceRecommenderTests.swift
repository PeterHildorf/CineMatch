//
//  OnDeviceRecommenderTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

/// En lille håndlavet modelfil: Se7en ligner Zodiac (samme instruktør) og Prisoners.
enum SampleModel {
    static let json = """
    {
      "formatVersion": 1, "modelVersion": "test", "qualityBoost": 0.02, "maxLiked": 25,
      "featureLabels": ["Story keywords", "Director"],
      "explainLabels": ["Director", "Keywords"],
      "strings": ["David Fincher", "serial killer"],
      "films": [
        {"id": 1, "title": "Se7en", "year": 1995, "genres": ["Crime"], "director": "David Fincher", "cast": "", "description": "", "runtime": 127, "rating": 4.2, "quality": 0},
        {"id": 2, "title": "Zodiac", "year": 2007, "genres": ["Crime"], "director": "David Fincher", "cast": "", "description": "", "runtime": 157, "rating": 4.0, "quality": 0},
        {"id": 3, "title": "Prisoners", "year": 2013, "genres": ["Thriller"], "director": "Denis Villeneuve", "cast": "", "description": "", "runtime": null, "rating": 4.0, "quality": 0},
        {"id": 4, "title": "Toy Story", "year": 1995, "genres": ["Animation"], "director": "John Lasseter", "cast": "", "description": "", "runtime": 81, "rating": 4.0, "quality": 0}
      ],
      "starterIDs": [1, 4],
      "neighbors": [
        [{"i": 1, "s": 0.5, "b": [[1, 0.4], [0, 0.1]], "x": [[0, 0], [1, 1]]},
         {"i": 2, "s": 0.3, "b": [[0, 0.3]], "x": [[1, 1]]}],
        [{"i": 0, "s": 0.5, "b": [[1, 0.4], [0, 0.1]], "x": [[0, 0], [1, 1]]},
         {"i": 2, "s": 0.2, "b": [[0, 0.2]], "x": [[1, 1]]}],
        [{"i": 0, "s": 0.3, "b": [[0, 0.3]], "x": [[1, 1]]},
         {"i": 1, "s": 0.2, "b": [[0, 0.2]], "x": [[1, 1]]}],
        []
      ]
    }
    """

    static func file() throws -> ModelFile {
        try JSONDecoder().decode(ModelFile.self, from: Data(json.utf8))
    }

    static func recommender() throws -> OnDeviceRecommender {
        try OnDeviceRecommender(file: file())
    }
}

struct OnDeviceRecommenderTests {

    @Test func oneLikeGivesItsNeighborsBestFirst() throws {
        let recommender = try SampleModel.recommender()

        let results = recommender.recommend(liked: [1])

        #expect(results.map(\.movieID) == [2, 3])
        #expect(results[0].score == 0.5)          // ½·0.5 + ½·0.5
        #expect(results[0].becauseMovieID == 1)
    }

    @Test func scoreMixesAverageAndBestMatchLikeAntonsModel() throws {
        let recommender = try SampleModel.recommender()

        let results = recommender.recommend(liked: [1, 2])

        // Prisoners: similarity 0.3 til Se7en og 0.2 til Zodiac → ½·0.25 + ½·0.3
        #expect(results.map(\.movieID) == [3])
        #expect(abs(results[0].score - 0.275) < 1e-9)
        #expect(results[0].becauseMovieID == 1)
    }

    @Test func excludedAndUnknownFilmsAreSkipped() throws {
        let recommender = try SampleModel.recommender()

        #expect(recommender.recommend(liked: [1], excluding: [2]).map(\.movieID) == [3])
        #expect(recommender.recommend(liked: [999]).isEmpty)
        #expect(recommender.recommend(liked: []).isEmpty)
    }

    @Test func breakdownAndSharedExplainTheMatch() throws {
        let recommender = try SampleModel.recommender()

        let zodiac = try #require(recommender.recommend(liked: [1]).first)

        #expect(zodiac.breakdown.map(\.label) == ["Director", "Story keywords"])
        #expect(zodiac.shared.first == OnDeviceRecommender.SharedFeature(label: "Director", values: ["David Fincher"]))
        #expect(recommender.reason(for: zodiac) == "Because you liked Se7en · Director: David Fincher")
    }

    @Test func searchIgnoresCaseAndPrefersTitleStart() throws {
        let recommender = try SampleModel.recommender()

        #expect(recommender.search("zod").map(\.id) == [2])
        #expect(recommender.search("STORY").map(\.id) == [4])
        #expect(recommender.search("  ").isEmpty)
    }

    @Test func starterFilmsComeFromFile() throws {
        #expect(try SampleModel.recommender().starterFilms.map(\.id) == [1, 4])
    }

    @Test func onboardingFilmsAreSpreadOverGenres() throws {
        // Crime har to film, Thriller og Animation én. Første runde: én fra hver genre.
        #expect(try SampleModel.recommender().onboardingFilms().map(\.id) == [1, 3, 4, 2])
        #expect(try SampleModel.recommender().onboardingFilms(limit: 2).map(\.id) == [1, 3])
    }

    @Test func unknownFormatVersionIsRejected() throws {
        let newer = SampleModel.json.replacingOccurrences(of: "\"formatVersion\": 1", with: "\"formatVersion\": 2")
        let file = try JSONDecoder().decode(ModelFile.self, from: Data(newer.utf8))

        #expect(throws: OnDeviceRecommender.LoadError.unsupportedFormat(2)) {
            try OnDeviceRecommender(file: file)
        }
    }
}

@MainActor
struct OnDeviceRecommendationServiceTests {

    private func makeService(_ signals: [TasteSignal]) throws -> OnDeviceRecommendationService {
        OnDeviceRecommendationService(
            store: ModelStore(preloaded: try SampleModel.recommender()),
            tasteSignalService: MockTasteSignalService(signals: signals)
        )
    }

    /// Fem likes, hvor kun Se7en (1) findes i den lille testmodel.
    private let fiveLikes = [1, 100, 101, 102, 103].map { TasteSignal(movieID: $0, kind: .like) }

    @Test func likesAreInputAndAnsweredFilmsAreExcluded() async throws {
        let service = try makeService(fiveLikes + [TasteSignal(movieID: 3, kind: .dislike)])

        try await service.requestRecompute()
        let recommendations = try await service.latestRecommendations()

        // Zodiac anbefales. Prisoners er disliket og må ikke komme med.
        #expect(recommendations.map(\.movieID) == [2])
        #expect(recommendations[0].rank == 1)
        #expect(recommendations[0].reason?.hasPrefix("Because you liked Se7en") == true)
    }

    @Test func tooFewLikesThrows() async throws {
        let fewLikes = try makeService(Array(fiveLikes.prefix(4)))
        await #expect(throws: RecommendationServiceError.tooFewLikes) {
            try await fewLikes.requestRecompute()
        }

        let onlyDislikes = try makeService((1...6).map { TasteSignal(movieID: $0, kind: .dislike) })
        await #expect(throws: RecommendationServiceError.tooFewLikes) {
            try await onlyDislikes.requestRecompute()
        }
    }
}
