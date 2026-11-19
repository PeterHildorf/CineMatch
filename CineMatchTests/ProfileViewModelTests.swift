//
//  ProfileViewModelTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct ProfileViewModelTests {

    private func makeStore() -> DailyPickStore {
        DailyPickStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, key: "test")
    }

    private let signals = [
        TasteSignal(movieID: 318, verdict: .fantastic),
        TasteSignal(movieID: 2571, verdict: .great),
        TasteSignal(movieID: 1, verdict: .bad),
        TasteSignal(movieID: 1265, verdict: .notSeen),
    ]

    @Test func loadCountsRatedAndLovedFilms() async {
        let viewModel = ProfileViewModel(email: "anna@example.com", signalServices: [MockTasteSignalService(signals: signals)], dailyPicks: makeStore())

        await viewModel.load()

        #expect(viewModel.ratedCount == 3, "\"Haven't seen\" tæller ikke som bedømt")
        #expect(viewModel.lovedCount == 2)
        #expect(viewModel.initial == "A")
    }

    @Test func startFreshDeletesAllRatingsAndTodaysPick() async {
        let swipe = MockTasteSignalService(signals: signals)
        let stars = MockTasteSignalService(signals: [TasteSignal(movieID: 99, verdict: .great)])
        let store = makeStore()
        let today = Date.now
        _ = store.pick(from: [318], on: today)
        store.markAnswered(movieID: 318, on: today)
        let viewModel = ProfileViewModel(email: nil, signalServices: [swipe, stars], dailyPicks: store)
        await viewModel.load()
        #expect(viewModel.streak == 1)

        let succeeded = await viewModel.startFresh()

        #expect(succeeded)
        #expect(swipe.signals.isEmpty)
        #expect(stars.signals.isEmpty)
        #expect(viewModel.ratedCount == 0)
        #expect(viewModel.streak == 0)
        #expect(!store.isDone(on: today))
    }

    @Test func startFreshShowsErrorWhenDeleteFails() async {
        let viewModel = ProfileViewModel(
            email: nil,
            signalServices: [MockTasteSignalService(signals: signals, errorToThrow: .network)],
            dailyPicks: makeStore()
        )

        let succeeded = await viewModel.startFresh()

        #expect(!succeeded)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func todayForgetsOldPicksAfterStartFresh() async {
        let signalService = MockTasteSignalService(signals: signals)
        let viewModel = RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: MockRecommendationService.sampleRecommendations),
            movieDataService: MockMovieDataService(),
            signalService: signalService,
            autoRecompute: true
        )
        await viewModel.load()
        guard case .loaded = viewModel.state else {
            Issue.record("Forventede anbefalinger før nulstilling")
            return
        }

        try? await signalService.deleteAllSignals()
        await viewModel.startOver()
        await viewModel.refresh()

        #expect(viewModel.state == .empty)
        #expect(viewModel.errorMessage == nil, "Tom-skærmen viser vejledningen, ikke en fejl")
    }
}
