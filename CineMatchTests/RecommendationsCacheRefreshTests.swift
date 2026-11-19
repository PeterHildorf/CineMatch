import Foundation
import Testing
@testable import CineMatch

@MainActor
struct RecommendationsCacheRefreshTests {
    private func makeViewModel() -> (RecommendationsViewModel, MockRecommendationService, MockTasteSignalService) {
        let signals = MockTasteSignalService(signals: (1...5).map {
            TasteSignal(movieID: $0, verdict: .great)
        })
        let result = [Recommendation(rank: 1, movieID: 100, score: 0.5, reason: "Based on your ratings")]
        let service = MockRecommendationService(nextResult: result)
        let movies = MockMovieDataService(titles: [Title(id: 100, tmdbId: 100, title: "A movie", year: 2000, genres: [])])
        return (
            RecommendationsViewModel(
                recommendationService: service, movieDataService: movies,
                signalService: signals, autoRecompute: true
            ),
            service,
            signals
        )
    }

    private func shownIDs(_ viewModel: RecommendationsViewModel) -> [Int] {
        guard case .loaded(let items) = viewModel.state else { return [] }
        return items.map(\.id)
    }

    @Test func unchangedInputsReuseResultsUntilTheirServiceCacheIsCleared() async {
        let (viewModel, service, _) = makeViewModel()
        await viewModel.refresh()
        let originalBatch = service.batch?.id
        #expect(service.recomputeCallCount == 1)
        #expect(shownIDs(viewModel) == [100])

        await viewModel.refresh()
        #expect(service.recomputeCallCount == 1, "A present result should still be reused")

        await service.clearRecommendations()
        await viewModel.refresh()

        #expect(service.recomputeCallCount == 2, "Same opinions need a new result after cache clearing")
        #expect(shownIDs(viewModel) == [100])
        #expect(service.batch?.id != originalBatch)
    }

    @Test func failedRecomputeCanRecoverWithoutChangingTheOpinions() async {
        let (viewModel, service, _) = makeViewModel()
        await viewModel.refresh()
        await service.clearRecommendations()
        service.recomputeError = .network
        await viewModel.recompute()
        #expect(viewModel.errorMessage != nil)

        service.recomputeError = nil
        await viewModel.refresh()

        #expect(service.recomputeCallCount == 3)
        #expect(viewModel.errorMessage == nil)
        #expect(shownIDs(viewModel) == [100])
    }

    @Test func failedOpinionReadDoesNotReplaceTheLastKnownProfile() async {
        let (viewModel, service, signals) = makeViewModel()
        await viewModel.refresh()
        signals.errorToThrow = .network

        await viewModel.refresh()
        #expect(service.recomputeCallCount == 1)
        #expect(shownIDs(viewModel) == [100])

        await service.clearRecommendations()
        await viewModel.refresh()
        #expect(service.recomputeCallCount == 1, "Do not recompute from a failed profile read")
        #expect(viewModel.state == .empty)

        signals.errorToThrow = nil
        await viewModel.refresh()
        #expect(service.recomputeCallCount == 2)
        #expect(shownIDs(viewModel) == [100])
    }

    @Test func startFreshStillWaitsForNewOpinionsWithoutShowingAnError() async throws {
        let (viewModel, service, signals) = makeViewModel()
        await viewModel.refresh()
        try await signals.deleteAllSignals()
        await viewModel.startOver()

        await viewModel.refresh()

        #expect(service.recomputeCallCount == 1)
        #expect(viewModel.state == .empty)
        #expect(viewModel.errorMessage == nil)
    }
}
