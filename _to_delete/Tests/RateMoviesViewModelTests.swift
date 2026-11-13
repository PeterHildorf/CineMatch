//
//  RateMoviesViewModelTests.swift
//  CineMatchTests
//

import Testing
@testable import CineMatch

@MainActor
struct RateMoviesViewModelTests {

    private let matrix = MockMovieDataService.sampleTitles[1]   // id 2571

    @Test func loadShowsTitlesAndExistingRatings() async {
        let ratings = MockRatingService(ratings: [Rating(movieID: 2571, stars: 4)])
        let viewModel = RateMoviesViewModel(movieDataService: MockMovieDataService(), ratingService: ratings)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.titles.count == MockMovieDataService.sampleTitles.count)
        #expect(viewModel.stars(for: matrix) == 4)
        #expect(viewModel.ratedCount == 1)
    }

    @Test func loadFailureShowsError() async {
        let movies = MockMovieDataService(errorToThrow: .fileNotFound)
        let viewModel = RateMoviesViewModel(movieDataService: movies, ratingService: MockRatingService())

        await viewModel.load()

        guard case .failed = viewModel.state else {
            Issue.record("Forventede .failed, fik \(viewModel.state)")
            return
        }
    }

    @Test func setStarsSavesRating() async throws {
        let ratings = MockRatingService()
        let viewModel = RateMoviesViewModel(movieDataService: MockMovieDataService(), ratingService: ratings)
        await viewModel.load()

        await viewModel.setStars(5, for: matrix)

        #expect(viewModel.stars(for: matrix) == 5)
        #expect(ratings.ratingsByMovieID[2571] == Rating(movieID: 2571, stars: 5))
    }

    @Test func tappingSameStarsAgainRemovesRating() async {
        let ratings = MockRatingService(ratings: [Rating(movieID: 2571, stars: 3)])
        let viewModel = RateMoviesViewModel(movieDataService: MockMovieDataService(), ratingService: ratings)
        await viewModel.load()

        await viewModel.setStars(3, for: matrix)

        #expect(viewModel.stars(for: matrix) == 0)
        #expect(ratings.ratingsByMovieID[2571] == nil)
    }

    @Test func failedSaveRevertsAndShowsError() async {
        let ratings = MockRatingService(ratings: [Rating(movieID: 2571, stars: 2)])
        let viewModel = RateMoviesViewModel(movieDataService: MockMovieDataService(), ratingService: ratings)
        await viewModel.load()
        ratings.errorToThrow = .network

        await viewModel.setStars(5, for: matrix)

        #expect(viewModel.stars(for: matrix) == 2, "Skal rulle tilbage til den gamle værdi")
        #expect(viewModel.errorMessage != nil)
    }

    @Test func needsFiveRatingsBeforeEnough() async {
        let viewModel = RateMoviesViewModel(movieDataService: MockMovieDataService(), ratingService: MockRatingService())
        await viewModel.load()

        for title in viewModel.titles.prefix(4) {
            await viewModel.setStars(4, for: title)
        }
        #expect(!viewModel.hasEnoughRatings)

        await viewModel.setStars(4, for: viewModel.titles[4])
        #expect(viewModel.hasEnoughRatings)
    }
}
