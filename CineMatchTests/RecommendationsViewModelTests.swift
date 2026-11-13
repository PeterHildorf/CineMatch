//
//  RecommendationsViewModelTests.swift
//  CineMatchTests
//

import Testing
@testable import CineMatch

@MainActor
struct RecommendationsViewModelTests {

    private func makeViewModel(_ service: MockRecommendationService) -> RecommendationsViewModel {
        RecommendationsViewModel(recommendationService: service, movieDataService: MockMovieDataService())
    }

    @Test func loadWithoutRecommendationsIsEmpty() async {
        let viewModel = makeViewModel(MockRecommendationService())

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test func loadJoinsRecommendationsWithTitlesInRankOrder() async throws {
        let shuffled = MockRecommendationService.sampleRecommendations.reversed()
        let viewModel = makeViewModel(MockRecommendationService(stored: Array(shuffled)))

        await viewModel.load()

        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Forventede .loaded, fik \(viewModel.state)")
            return
        }
        #expect(items.map(\.recommendation.rank) == [1, 2, 3, 4, 5])
        #expect(items[0].displayTitle == "The Matrix")
    }

    @Test func unknownMovieGetsFallbackTitle() async throws {
        let unknown = Recommendation(rank: 1, movieID: 999_999, score: nil, reason: nil)
        let viewModel = makeViewModel(MockRecommendationService(stored: [unknown]))

        await viewModel.load()

        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Forventede .loaded, fik \(viewModel.state)")
            return
        }
        #expect(items[0].title == nil)
        #expect(items[0].displayTitle == "Movie #999999")
    }

    @Test func recomputeFetchesNewRecommendations() async {
        let service = MockRecommendationService()
        let viewModel = makeViewModel(service)
        await viewModel.load()

        await viewModel.recompute()

        #expect(service.recomputeCallCount == 1)
        #expect(!viewModel.isRecomputing)
        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Forventede .loaded, fik \(viewModel.state)")
            return
        }
        #expect(items.count == 5)
    }

    @Test(arguments: [
        RecommendationServiceError.tooFewLikes,
        .notReady,
        .unauthorized,
        .network,
        .unknown,
    ])
    func recomputeFailureKeepsOldListAndShowsError(error: RecommendationServiceError) async {
        let service = MockRecommendationService(stored: MockRecommendationService.sampleRecommendations)
        let viewModel = makeViewModel(service)
        await viewModel.load()
        service.recomputeError = error

        await viewModel.recompute()

        #expect(viewModel.errorMessage != nil)
        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Den gamle liste skal blive stående, fik \(viewModel.state)")
            return
        }
        #expect(items.count == 5)
    }

    @Test func tooFewLikesMentionsMinimum() async {
        let service = MockRecommendationService()
        service.recomputeError = .tooFewLikes
        let viewModel = makeViewModel(service)

        await viewModel.recompute()

        #expect(viewModel.errorMessage?.contains("\(TasteViewModel.minimumLikes)") == true)
    }

    @Test func loadFailureShowsFailedState() async {
        let service = MockRecommendationService()
        service.loadError = .network
        let viewModel = makeViewModel(service)

        await viewModel.load()

        guard case .failed = viewModel.state else {
            Issue.record("Forventede .failed, fik \(viewModel.state)")
            return
        }
    }
}
