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

/// "Seen it": like/dislike på en anbefaling, og næste kandidat rykker op.
@MainActor
struct SeenItTests {

    /// 12 kandidater (film 101–112), så der er 2 i reserve bag de 10 viste.
    private static let twelve = (1...12).map { Recommendation(rank: $0, movieID: 100 + $0, score: nil, reason: nil) }

    private func makeViewModel(
        _ service: MockRecommendationService = MockRecommendationService(stored: twelve),
        signals: MockTasteSignalService? = MockTasteSignalService()
    ) -> RecommendationsViewModel {
        RecommendationsViewModel(recommendationService: service, movieDataService: MockMovieDataService(), signalService: signals)
    }

    private func shownIDs(_ viewModel: RecommendationsViewModel) -> [Int] {
        guard case .loaded(let items) = viewModel.state else { return [] }
        return items.map(\.recommendation.movieID)
    }

    private func item(_ viewModel: RecommendationsViewModel, movieID: Int) -> RecommendationsViewModel.Item? {
        guard case .loaded(let items) = viewModel.state else { return nil }
        return items.first { $0.recommendation.movieID == movieID }
    }

    @Test func seenMovieIsReplacedByNextCandidate() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        await viewModel.markSeen(try #require(item(viewModel, movieID: 103)), liked: true)

        #expect(shownIDs(viewModel) == [101, 102, 104, 105, 106, 107, 108, 109, 110, 111])
    }

    @Test(arguments: [true, false])
    func answerIsSavedAsFeedback(liked: Bool) async throws {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals: signals)
        await viewModel.load()

        await viewModel.markSeen(try #require(item(viewModel, movieID: 101)), liked: liked)

        #expect(signals.signals == [TasteSignal(movieID: 101, kind: liked ? .like : .dislike, source: .feedback)])
    }

    @Test func failedSaveKeepsMovieAndShowsError() async throws {
        let viewModel = makeViewModel(signals: MockTasteSignalService(errorToThrow: .network))
        await viewModel.load()
        let before = shownIDs(viewModel)

        await viewModel.markSeen(try #require(item(viewModel, movieID: 105)), liked: true)

        #expect(shownIDs(viewModel) == before)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func runningOutOfCandidatesRecomputes() async throws {
        let service = MockRecommendationService(stored: Self.twelve)
        let viewModel = makeViewModel(service)
        await viewModel.load()

        // 12 kandidater: efter 3 "Seen it" er der kun 9 tilbage → nye anbefalinger.
        for movieID in [101, 102] {
            await viewModel.markSeen(try #require(item(viewModel, movieID: movieID)), liked: true)
        }
        #expect(service.recomputeCallCount == 0)
        await viewModel.markSeen(try #require(item(viewModel, movieID: 103)), liked: true)

        #expect(service.recomputeCallCount == 1)
    }

    @Test func replacementDoesNotLookUpShownMoviesAgain() async throws {
        let media = MockTitleMediaService()
        let viewModel = RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: MockRecommendationService.sampleRecommendations),
            movieDataService: MockMovieDataService(),
            mediaService: media,
            signalService: MockTasteSignalService()
        )
        await viewModel.load()
        let lookups = media.requestedIDs.count

        await viewModel.markSeen(try #require(item(viewModel, movieID: 2571)), liked: true)

        #expect(media.requestedIDs.count == lookups)
    }

    @Test func withoutSignalServiceSeenItIsHidden() async {
        let viewModel = makeViewModel(signals: nil)

        #expect(!viewModel.canMarkSeen)
    }
}
