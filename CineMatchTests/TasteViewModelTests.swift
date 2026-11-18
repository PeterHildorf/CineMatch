//
//  TasteViewModelTests.swift
//  CineMatchTests
//

import Testing
@testable import CineMatch

@MainActor
struct TasteViewModelTests {

    private func makeViewModel(_ signals: MockTasteSignalService = MockTasteSignalService()) -> TasteViewModel {
        TasteViewModel(movieDataService: MockMovieDataService(), tasteSignalService: signals)
    }

    @Test func loadShowsFirstFilmAndSkipsAnsweredOnes() async {
        let signals = MockTasteSignalService(signals: [TasteSignal(movieID: 318, verdict: .great)])
        let viewModel = makeViewModel(signals)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.current?.id == 2571, "Shawshank (318) er allerede bedømt og springes over")
        #expect(viewModel.likeCount == 1)
    }

    @Test func haventSeenFromEarlierIsNotShownAgain() async {
        let signals = MockTasteSignalService(signals: [TasteSignal(movieID: 318, verdict: .notSeen)])
        let viewModel = makeViewModel(signals)

        await viewModel.load()

        #expect(viewModel.current?.id == 2571)
        #expect(viewModel.seenCount == 0)
    }

    @Test func loadFailureShowsError() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(errorToThrow: .fileNotFound),
            tasteSignalService: MockTasteSignalService()
        )

        await viewModel.load()

        guard case .failed = viewModel.state else {
            Issue.record("Forventede .failed, fik \(viewModel.state)")
            return
        }
    }

    @Test func everyVerdictIsSavedWithItsScore() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        await viewModel.rate(.horrible)    // Shawshank
        await viewModel.rate(.bad)         // The Matrix
        await viewModel.rate(.great)       // Toy Story
        await viewModel.rate(.fantastic)   // Groundhog Day
        await viewModel.rate(.notSeen)     // The Shining

        let scores = Dictionary(uniqueKeysWithValues: signals.signals.map { ($0.movieID, $0.score) })
        #expect(scores == [318: 1, 2571: 2, 1: 3, 1265: 5, 1258: 0])
        #expect(signals.kindByMovieID == [318: .dislike, 2571: .dislike, 1: .like, 1265: .like, 1258: .unseen])
        #expect(viewModel.likeCount == 2)
        #expect(viewModel.seenCount == 4)
        #expect(viewModel.current == nil)
    }

    @Test func undoBringsFilmBackAndDeletesAnswer() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        await viewModel.rate(.fantastic)

        await viewModel.undo()

        #expect(viewModel.current?.id == 318)
        #expect(viewModel.likeCount == 0)
        #expect(signals.signals.isEmpty)
        #expect(!viewModel.canUndo)
    }

    @Test func undoAlsoWorksForHaventSeen() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        await viewModel.rate(.notSeen)

        await viewModel.undo()

        #expect(viewModel.current?.id == 318)
        #expect(signals.signals.isEmpty)
    }

    @Test func failedSaveShowsFilmAgainWithError() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        signals.errorToThrow = .network

        await viewModel.rate(.great)

        #expect(viewModel.current?.id == 318, "Kortet skal vises igen")
        #expect(viewModel.likeCount == 0)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.canUndo)
    }

    @Test func needsFiveGreatOrFantasticBeforeEnough() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            tasteSignalService: MockTasteSignalService()
        )
        await viewModel.load()

        for _ in 0..<4 { await viewModel.rate(.great) }
        await viewModel.rate(.bad)
        await viewModel.rate(.notSeen)
        #expect(!viewModel.hasEnoughLikes, "Bad og Haven't seen tæller ikke")

        await viewModel.rate(.fantastic)
        #expect(viewModel.hasEnoughLikes)
    }

    @Test func onboardingNeedsTenAnswersAndFiveLikes() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            tasteSignalService: MockTasteSignalService()
        )
        await viewModel.load()

        for _ in 0..<5 { await viewModel.rate(.great) }
        #expect(!viewModel.isReadyForPicks, "5 likes, men kun 5 film")
        for _ in 0..<5 { await viewModel.rate(.notSeen) }
        #expect(viewModel.isReadyForPicks)
    }

    @Test func syncRemovesMoviesRatedElsewhere() async throws {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        try await signals.save(TasteSignal(movieID: 2571, verdict: .great))   // fx i Search
        await viewModel.syncAnswers()

        #expect(!viewModel.queue.contains { $0.id == 2571 })
        #expect(viewModel.likeCount == 1)
    }
}
