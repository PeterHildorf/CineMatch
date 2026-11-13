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
        let signals = MockTasteSignalService(signals: [TasteSignal(movieID: 318, kind: .like)])
        let viewModel = makeViewModel(signals)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.current?.id == 2571, "Shawshank (318) er allerede liket og springes over")
        #expect(viewModel.likeCount == 1)
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

    @Test func likeAndDislikeAreSavedAndShowNextFilm() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        await viewModel.like()        // Shawshank
        await viewModel.dislike()     // The Matrix

        #expect(signals.kindByMovieID == [318: .like, 2571: .dislike])
        #expect(viewModel.likeCount == 1)
        #expect(viewModel.dislikeCount == 1)
        #expect(viewModel.current?.id == 1)
    }

    @Test func skipIsNotSaved() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()

        viewModel.skip()

        #expect(signals.signals.isEmpty)
        #expect(viewModel.current?.id == 2571)
    }

    @Test func undoBringsFilmBackAndDeletesAnswer() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        await viewModel.like()

        await viewModel.undo()

        #expect(viewModel.current?.id == 318)
        #expect(viewModel.likeCount == 0)
        #expect(signals.signals.isEmpty)
        #expect(!viewModel.canUndo)
    }

    @Test func failedSaveShowsFilmAgainWithError() async {
        let signals = MockTasteSignalService()
        let viewModel = makeViewModel(signals)
        await viewModel.load()
        signals.errorToThrow = .network

        await viewModel.like()

        #expect(viewModel.current?.id == 318, "Kortet skal vises igen")
        #expect(viewModel.likeCount == 0)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.canUndo)
    }

    @Test func needsFiveLikesBeforeEnough() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        for _ in 0..<4 { await viewModel.like() }
        #expect(!viewModel.hasEnoughLikes)

        await viewModel.like()
        #expect(viewModel.hasEnoughLikes)
        #expect(viewModel.current == nil, "Alle 5 testfilm er besvaret")
    }
}
