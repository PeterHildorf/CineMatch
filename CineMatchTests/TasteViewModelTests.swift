//
//  TasteViewModelTests.swift
//  CineMatchTests
//

import Foundation
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

    @Test func recentlySkippedFilmIsNotShownAgain() async {
        let skipped = TasteSignal(movieID: 318, verdict: .notSeen, answeredAt: .now.addingTimeInterval(-24 * 60 * 60))
        let viewModel = makeViewModel(MockTasteSignalService(signals: [skipped]))

        await viewModel.load()

        #expect(viewModel.current?.id == 2571)
        #expect(!viewModel.queue.contains { $0.id == 318 })
        #expect(viewModel.seenCount == 0)
    }

    @Test func filmSkippedLongAgoComesBackLast() async {
        let longAgo = Date.now.addingTimeInterval(-Verdict.notSeenCooldown - 60)
        let skipped = TasteSignal(movieID: 318, verdict: .notSeen, answeredAt: longAgo)
        let viewModel = makeViewModel(MockTasteSignalService(signals: [skipped]))

        await viewModel.load()

        #expect(viewModel.current?.id == 2571, "Nye film først")
        #expect(viewModel.queue.last?.id == 318, "Shawshank kommer igen – bagerst")
    }

    @Test func ratedFilmNeverComesBack() async {
        let longAgo = Date.now.addingTimeInterval(-Verdict.notSeenCooldown * 10)
        let rated = TasteSignal(movieID: 318, verdict: .neutral, answeredAt: longAgo)
        let viewModel = makeViewModel(MockTasteSignalService(signals: [rated]))

        await viewModel.load()

        #expect(!viewModel.queue.contains { $0.id == 318 })
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
        await viewModel.rate(.neutral)     // Toy Story
        await viewModel.rate(.great)       // Groundhog Day
        await viewModel.rate(.fantastic)   // The Shining

        let scores = Dictionary(uniqueKeysWithValues: signals.signals.map { ($0.movieID, $0.score) })
        #expect(scores == [318: 1, 2571: 2, 1: 3, 1265: 4, 1258: 5])
        #expect(signals.kindByMovieID == [318: .dislike, 2571: .dislike, 1: .neutral, 1265: .like, 1258: .like])
        #expect(viewModel.likeCount == 2, "Neutral er ikke et like")
        #expect(viewModel.seenCount == 5)
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

    @Test func haventSeenIsSavedAsZero() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        await viewModel.rate(.notSeen)

        #expect(signals.signals.map(\.score) == [0])
        #expect(signals.kindByMovieID == [318: .unseen])
        #expect(viewModel.current?.id == 2571)
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
        await viewModel.rate(.neutral)
        await viewModel.rate(.notSeen)
        #expect(!viewModel.hasEnoughLikes, "Bad, Neutral og Haven't seen tæller ikke")

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

    @Test func shuffledInBlocksKeepsEveryFilmInItsBlock() {
        let titles = (1...120).map { Title(id: $0, tmdbId: $0, title: "Film \($0)", year: 2000, genres: []) }
        let shuffled = TasteViewModel.shuffledInBlocks(titles, blockSize: 50)

        #expect(shuffled.count == titles.count)
        #expect(Set(shuffled.map(\.id)) == Set(titles.map(\.id)))
        // De 50 mest kendte film bliver i de første 50 pladser osv.
        #expect(Set(shuffled[0..<50].map(\.id)) == Set(1...50))
        #expect(Set(shuffled[50..<100].map(\.id)) == Set(51...100))
        #expect(Set(shuffled[100..<120].map(\.id)) == Set(101...120))
    }

    @Test func loadUsesTheGivenOrderForNewFilms() async {
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: MockTasteSignalService(),
            order: { $0.reversed() }
        )
        await viewModel.load()

        let titles = try? await MockMovieDataService().allTitles()
        #expect(viewModel.current?.id == titles?.last?.id)
    }
}
