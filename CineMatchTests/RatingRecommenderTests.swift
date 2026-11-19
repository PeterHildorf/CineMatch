//
//  RatingRecommenderTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

/// Antons nye model på en lille håndlavet fil, så tallene kan regnes efter i hånden.
struct RatingRecommenderTests {

    /// 4 film. Kun Letterboxd-naboer tæller (vægt 1), og `personalFromRatings = 0`,
    /// så brugerens gennemsnit er præcis gennemsnittet af dommene.
    private static func makeFile(formatVersion: Int = 2) throws -> RatingModelFile {
        let json = """
        {
          "ratingFormatVersion": \(formatVersion),
          "shrink": 0.5,
          "globalMean": 3.0,
          "personalFromRatings": 0,
          "weights": { "letterboxd": 1, "movielens": 0, "tag": 0, "filmDeviation": 0, "intercept": 0 },
          "films": [
            { "id": 10, "title": "Liked", "filmDeviation": 0 },
            { "id": 20, "title": "Close to liked", "filmDeviation": 0 },
            { "id": 30, "title": "A bit like liked", "filmDeviation": 0 },
            { "id": 40, "title": "Disliked", "filmDeviation": 0 }
          ],
          "letterboxdNeighbors": [ [[1, 1.0]], [[0, 1.0]], [[0, 0.5]], [] ],
          "movielensNeighbors": [ [], [], [], [] ],
          "tagNeighbors": [ [], [], [], [] ]
        }
        """
        return try JSONDecoder().decode(RatingModelFile.self, from: Data(json.utf8))
    }

    @Test func predictsFromNeighbours() throws {
        let model = try RatingRecommender(file: Self.makeFile())
        // Gennemsnit 3 → afvigelse +2 for film 10.
        // Film 20: 3 + 1.0·2 / (1.0 + 0.5) = 4.333…   Film 30: 3 + 0.5·2 / (0.5 + 0.5) = 4.0
        let results = model.recommend(
            ratings: [.init(movieID: 10, score: 5), .init(movieID: 40, score: 1)],
            excluding: [10, 40],
            limit: 5
        )
        #expect(results.map(\.movieID) == [20, 30])
        #expect(abs(results[0].predicted - 13.0 / 3.0) < 1e-9)
        #expect(abs(results[1].predicted - 4.0) < 1e-9)
        #expect(results.allSatisfy { $0.becauseMovieID == 10 })
        #expect(model.modelVersion == "rating-v2")
    }

    @Test func noRatingsGivesNoRecommendations() throws {
        let model = try RatingRecommender(file: Self.makeFile())
        #expect(model.recommend(ratings: [.init(movieID: 999, score: 5)]).isEmpty)
    }

    @Test func rejectsUnknownFormat() throws {
        #expect(throws: RatingRecommender.LoadError.unsupportedFormat(99)) {
            try RatingRecommender(file: Self.makeFile(formatVersion: 99))
        }
    }

    @Test func bundledFileLoads() async throws {
        guard RatingModelStore.isAvailable() else { return }
        let model = try await RatingModelStore().recommender()
        #expect(model.filmCount > 0)
    }
}
