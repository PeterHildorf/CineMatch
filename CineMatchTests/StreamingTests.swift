//
//  StreamingTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct StreamingServiceTests {

    @Test func matchesByTMDBIdOrByName() {
        #expect(StreamingService.netflix.matches(StreamingProvider(id: 8, name: "Netflix", logoURL: nil)))
        #expect(StreamingService.netflix.matches(StreamingProvider(id: 9_999, name: "Netflix basic with Ads", logoURL: nil)))
        #expect(StreamingService.disneyPlus.matches(StreamingProvider(id: 9_999, name: "Disney Plus", logoURL: nil)))
        #expect(StreamingService.tv2Play.matches(StreamingProvider(id: 9_999, name: "TV 2 Play", logoURL: nil)))
    }

    @Test func appleTVStoreIsNotAppleTVPlus() {
        #expect(!StreamingService.appleTVPlus.matches(StreamingProvider(id: 2, name: "Apple TV", logoURL: nil)))
        #expect(StreamingService.appleTVPlus.matches(StreamingProvider(id: 9_999, name: "Apple TV+", logoURL: nil)))
    }

    @Test func providerInServicesPicksMostPopularOfUsersServices() {
        let media = TitleMedia(tmdbId: 1, posterURL: nil, streaming: [
            StreamingProvider(id: 8, name: "Netflix", logoURL: nil),
            StreamingProvider(id: 76, name: "Viaplay", logoURL: nil),
        ])

        #expect(media.provider(in: [.viaplay, .hboMax])?.name == "Viaplay")
        #expect(media.provider(in: [.hboMax]) == nil)
        #expect(media.provider(in: []) == nil)
    }

    @Test func localPreferencesSurviveANewInstance() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        let saved = StreamingPreferences(services: [.netflix, .tv2Play], onlyMyServices: true)

        #expect(try await LocalPreferencesService(userID: "a", defaults: defaults).streamingPreferences() == nil)
        try await LocalPreferencesService(userID: "a", defaults: defaults).saveStreamingPreferences(saved)

        #expect(try await LocalPreferencesService(userID: "a", defaults: defaults).streamingPreferences() == saved)
    }

    /// En ny bruger på samme telefon skal selv vælge tjenester – ikke arve den forriges.
    @Test func localPreferencesArePerUser() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        try await LocalPreferencesService(userID: "a", defaults: defaults)
            .saveStreamingPreferences(StreamingPreferences(services: [.netflix]))

        #expect(try await LocalPreferencesService(userID: "b", defaults: defaults).streamingPreferences() == nil)
    }

    /// `-freshUser` glemmer valget, så tjenesterne bliver spurgt om først igen.
    @Test func deletedPreferencesNeedSetupAgain() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        let preferences = LocalPreferencesService(userID: "a", defaults: defaults)
        try await preferences.saveStreamingPreferences(StreamingPreferences(services: [.netflix]))
        try await preferences.deleteStreamingPreferences()

        #expect(await StreamingServicesViewModel(preferencesService: preferences).needsSetup())
    }
}

@MainActor
struct StreamingServicesViewModelTests {

    @Test func needsSetupUntilServicesAreSaved() async {
        let preferences = MockPreferencesService()
        let viewModel = StreamingServicesViewModel(preferencesService: preferences)
        #expect(await viewModel.needsSetup())

        await viewModel.load()
        viewModel.toggle(.netflix)
        viewModel.toggle(.viaplay)
        viewModel.toggle(.viaplay)   // fravalgt igen
        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(preferences.stored?.services == [.netflix])
        #expect(await !viewModel.needsSetup())
    }

    @Test func savingNoServicesTurnsOffOnlyMyServices() async {
        let preferences = MockPreferencesService(stored: StreamingPreferences(services: [.netflix], onlyMyServices: true))
        let viewModel = StreamingServicesViewModel(preferencesService: preferences)
        await viewModel.load()

        viewModel.toggle(.netflix)
        _ = await viewModel.save()

        #expect(preferences.stored == StreamingPreferences(services: [], onlyMyServices: false))
    }

    @Test func saveFailureShowsErrorAndStaysOpen() async {
        let preferences = MockPreferencesService()
        preferences.saveError = URLError(.notConnectedToInternet)
        let viewModel = StreamingServicesViewModel(preferencesService: preferences)
        await viewModel.load()

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.errorMessage != nil)
    }
}

@MainActor
struct OnlyMyServicesTests {

    /// The Matrix (2571) er på Netflix, The Shawshank Redemption (318) på Viaplay, resten intet sted.
    private func makeViewModel(_ preferences: MockPreferencesService) -> RecommendationsViewModel {
        let viaplay = TitleMedia(tmdbId: 278, posterURL: nil, streaming: [StreamingProvider(id: 76, name: "Viaplay", logoURL: nil)])
        return RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: MockRecommendationService.sampleRecommendations),
            movieDataService: MockMovieDataService(),
            mediaService: MockTitleMediaService(mediaByTitleID: [2571: MockTitleMediaService.sampleMedia, 318: viaplay]),
            preferencesService: preferences
        )
    }

    private func titles(_ viewModel: RecommendationsViewModel) -> [String] {
        guard case .loaded(let items) = viewModel.state else { return [] }
        return items.map(\.displayTitle)
    }

    @Test func withoutFilterTopFiveAreShown() async {
        let viewModel = makeViewModel(MockPreferencesService(stored: StreamingPreferences(services: [.netflix])))

        await viewModel.load()

        #expect(titles(viewModel).count == 5)
        #expect(viewModel.canFilterByServices)
        #expect(viewModel.filterNote == nil)
    }

    @Test func filterKeepsOnlyMoviesOnUsersServices() async {
        let preferences = MockPreferencesService(stored: StreamingPreferences(services: [.netflix, .viaplay], onlyMyServices: true))
        let viewModel = makeViewModel(preferences)

        await viewModel.load()

        #expect(titles(viewModel) == ["The Matrix", "The Shawshank Redemption"])
        #expect(viewModel.filterNote == "Only 2 of your top 5 movies are on your services right now.")
        #expect(!viewModel.isFiltering)
    }

    @Test func turningFilterOnIsSavedAndApplied() async {
        let preferences = MockPreferencesService(stored: StreamingPreferences(services: [.netflix]))
        let viewModel = makeViewModel(preferences)
        await viewModel.load()

        await viewModel.setOnlyMyServices(true)

        #expect(titles(viewModel) == ["The Matrix"])
        #expect(preferences.stored?.onlyMyServices == true)

        await viewModel.setOnlyMyServices(false)
        #expect(titles(viewModel).count == 5)
    }

    @Test func filterWithoutServicesIsIgnored() async {
        let viewModel = makeViewModel(MockPreferencesService(stored: StreamingPreferences(services: [], onlyMyServices: true)))

        await viewModel.load()

        #expect(titles(viewModel).count == 5)
        #expect(!viewModel.canFilterByServices)
    }
}
