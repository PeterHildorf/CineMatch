//
//  DailyPickTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

/// "Today's pick": én film om dagen, streak og "Another pick".
@MainActor
struct DailyPickStoreTests {

    private let monday = Date(timeIntervalSince1970: 1_800_000_000)
    private var tuesday: Date { monday.addingTimeInterval(24 * 3600) }
    private var wednesday: Date { monday.addingTimeInterval(48 * 3600) }

    private func makeStore() -> DailyPickStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return DailyPickStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, key: "test", calendar: calendar)
    }

    @Test func samePickAllDayAndANewOneTomorrow() {
        let store = makeStore()

        #expect(store.pick(from: [1, 2, 3], on: monday) == 1)
        #expect(store.pick(from: [1, 2, 3], on: monday.addingTimeInterval(3600)) == 1)
        #expect(store.pick(from: [1, 2, 3], on: tuesday) == 2, "Gårsdagens pick bliver ikke dagens igen")
    }

    @Test func answeringGivesANewPickAndBuildsAStreak() {
        let store = makeStore()
        _ = store.pick(from: [1, 2, 3], on: monday)
        store.markAnswered(movieID: 1, on: monday)

        #expect(store.pick(from: [2, 3], on: monday) == 2, "Set den allerede → næste film bliver aftenens pick")
        #expect(store.isDone(on: monday))
        #expect(store.streak(on: monday) == 1)

        let tuesdayPick = store.pick(from: [2, 3], on: tuesday)
        #expect(tuesdayPick == 3, "Mandagens pick bliver ikke tirsdagens igen")
        #expect(store.streak(on: tuesday) == 1, "Streaken knækker ikke, før dagen er omme")
        store.markAnswered(movieID: 3, on: tuesday)
        #expect(store.streak(on: tuesday) == 2)

        #expect(store.streak(on: wednesday.addingTimeInterval(24 * 3600)) == 0, "En dag uden dom nulstiller")
    }

    @Test func anotherPickSkipsTheMovieForGood() {
        let store = makeStore()
        _ = store.pick(from: [1, 2, 3], on: monday)

        store.pass(movieID: 1, on: monday)

        #expect(store.pick(from: [1, 2, 3], on: monday) == 2)
        #expect(store.pick(from: [1, 3], on: tuesday) == 3)
    }

    @Test func aNewPickIsChosenIfTodaysDisappears() {
        let store = makeStore()
        _ = store.pick(from: [1, 2], on: monday)

        // Fx bedømt i Swipe i mellemtiden.
        #expect(store.pick(from: [2], on: monday) == 2)
        #expect(!store.isDone(on: monday))
    }

    @Test func answeringAnotherMovieDoesNotFinishTheDay() {
        let store = makeStore()
        _ = store.pick(from: [1, 2], on: monday)

        store.markAnswered(movieID: 2, on: monday)

        #expect(!store.isDone(on: monday))
    }
}

/// Today-skærmens ViewModel: dagens pick forrest, og "Seen it" på den klarer dagen.
@MainActor
struct TodayViewModelTests {

    private func makeViewModel(
        signals: MockTasteSignalService = MockTasteSignalService(),
        service: MockRecommendationService? = nil
    ) -> (RecommendationsViewModel, MockRecommendationService) {
        let service = service ?? MockRecommendationService(stored: DemoData.recommendations)
        let viewModel = RecommendationsViewModel(
            recommendationService: service,
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            signalService: signals,
            dailyPicks: DailyPickStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, key: "test"),
            autoRecompute: true,
            title: "Today"
        )
        return (viewModel, service)
    }

    private func shownIDs(_ viewModel: RecommendationsViewModel) -> [Int] {
        guard case .loaded(let items) = viewModel.state else { return [] }
        return items.map(\.id)
    }

    @Test func dailyPickIsFirst() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load()

        #expect(viewModel.dailyPickID == DemoData.recommendations[0].movieID)
        #expect(shownIDs(viewModel).first == viewModel.dailyPickID)
    }

    @Test func ratingTheDailyPickShowsTheNextOne() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        guard case .loaded(let items) = viewModel.state else { Issue.record("Ingen liste"); return }
        let seen = try #require(items.first)

        await viewModel.markSeen(seen, verdict: .fantastic)

        #expect(viewModel.dailyPickID == items[1].id, "Næste anbefaling rykker op som aftenens pick")
        #expect(shownIDs(viewModel).first == viewModel.dailyPickID)
        #expect(!shownIDs(viewModel).contains(seen.id))
        #expect(viewModel.streak == 1)
    }

    @Test func anotherPickShowsADifferentMovie() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        let first = viewModel.dailyPickID

        await viewModel.anotherDailyPick()

        #expect(viewModel.dailyPickID != nil)
        #expect(viewModel.dailyPickID != first)
        #expect(shownIDs(viewModel).first == viewModel.dailyPickID)
    }

    @Test func refreshRecomputesOnlyWhenAnswersChange() async throws {
        let signals = MockTasteSignalService()
        let (viewModel, service) = makeViewModel(
            signals: signals,
            service: MockRecommendationService(nextResult: DemoData.recommendations)
        )

        await viewModel.refresh()
        #expect(service.recomputeCallCount == 1, "Første gang beregnes der altid")
        await viewModel.refresh()
        #expect(service.recomputeCallCount == 1, "Ingen nye svar → ingen ny beregning")

        try await signals.save(TasteSignal(movieID: 807, verdict: .great))
        await viewModel.refresh()
        #expect(service.recomputeCallCount == 2)
    }

    @Test func tooFewAnswersShowsEmptyWithHint() async {
        let service = MockRecommendationService()
        service.recomputeError = .tooFewLikes
        let (viewModel, _) = makeViewModel(service: service)

        await viewModel.refresh()

        #expect(viewModel.state == .empty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func todayShowsPickPlusTopTenThenMoreOnRequest() async {
        // 25 kandidater.
        let many = (1...25).map { Recommendation(rank: $0, movieID: 1000 + $0, score: nil, reason: nil) }
        let (viewModel, _) = makeViewModel(service: MockRecommendationService(stored: many))
        await viewModel.load()

        #expect(shownIDs(viewModel).count == 11, "Dagens pick + top 10")
        #expect(viewModel.canShowMore)

        await viewModel.showMore()

        #expect(shownIDs(viewModel).count == 21, "Dagens pick + 20")
        #expect(!viewModel.canShowMore)
    }
}
