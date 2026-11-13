//
//  MockRatingService.swift
//  CineMatch
//

/// Falsk bedømmelses-service til previews og tests. Gemmer i hukommelsen.
final class MockRatingService: RatingService {
    /// Bedømmelser pr. MovieLens-id.
    private(set) var ratingsByMovieID: [Int: Rating]
    /// Sæt en fejl i tests for at simulere, at Supabase ikke svarer.
    var errorToThrow: RatingServiceError?

    private(set) var saveCallCount = 0

    init(ratings: [Rating] = [], errorToThrow: RatingServiceError? = nil) {
        self.ratingsByMovieID = Dictionary(uniqueKeysWithValues: ratings.map { ($0.movieID, $0) })
        self.errorToThrow = errorToThrow
    }

    func allRatings() async throws -> [Rating] {
        if let errorToThrow { throw errorToThrow }
        return Array(ratingsByMovieID.values)
    }

    func save(_ rating: Rating) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        ratingsByMovieID[rating.movieID] = rating
    }

    func deleteRating(movieID: Int) async throws {
        if let errorToThrow { throw errorToThrow }
        ratingsByMovieID[movieID] = nil
    }
}
