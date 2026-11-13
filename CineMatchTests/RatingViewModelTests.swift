//
//  RatingViewModelTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct RatingViewModelTests {

    private func makeViewModel(_ signals: MockTasteSignalService = MockTasteSignalService()) -> RatingViewModel {
        RatingViewModel(movieDataService: MockMovieDataService(), signalService: signals)
    }

    private var matrix: Title { MockMovieDataService.sampleTitles[1] }

    @Test func loadShowsAllMoviesAndSavedRatings() async {
        let signals = MockTasteSignalService(signals: [
            TasteSignal(movieID: 2571, kind: .like, rating: 4.5),
            TasteSignal(movieID: 318, kind: .like),   // swipe uden stjerner tæller ikke
        ])
        let viewModel = makeViewModel(signals)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.titles.count == 5)
        #expect(viewModel.rating(for: matrix) == 4.5)
        #expect(viewModel.ratedCount == 1)
    }

    @Test func ratingIsSavedWithStarsAndDerivedKind() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        await viewModel.rate(matrix, stars: 2.0)
        await viewModel.rate(matrix, stars: 4.5)   // ændret

        #expect(signals.signals == [TasteSignal(movieID: 2571, kind: .like, rating: 4.5)])
        #expect(viewModel.rating(for: matrix) == 4.5)
    }

    @Test func sameRatingAgainRemovesIt() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        await viewModel.rate(matrix, stars: 3.5)
        await viewModel.rate(matrix, stars: 3.5)

        #expect(signals.signals.isEmpty)
        #expect(viewModel.rating(for: matrix) == 0)
    }

    @Test func needsFiveRatingsBeforeEnough() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        for title in MockMovieDataService.sampleTitles.prefix(4) {
            await viewModel.rate(title, stars: 4)
        }
        #expect(!viewModel.hasEnoughRatings)
        #expect(viewModel.progressText == "Rate 1 more movie with stars")

        await viewModel.rate(MockMovieDataService.sampleTitles[4], stars: 1)
        #expect(viewModel.hasEnoughRatings)
    }

    @Test func failedSaveRestoresPreviousRating() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        await viewModel.rate(matrix, stars: 4)

        signals.errorToThrow = .network
        await viewModel.rate(matrix, stars: 1)

        #expect(viewModel.rating(for: matrix) == 4)
        #expect(viewModel.errorMessage != nil)
    }
}
