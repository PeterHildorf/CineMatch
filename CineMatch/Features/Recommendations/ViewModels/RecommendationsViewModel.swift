//
//  RecommendationsViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// Henter top 10 fra én model og kobler dem sammen med filmdata.
@Observable
@MainActor
final class RecommendationsViewModel {
    /// En anbefaling + filmen den handler om. `title` er nil, hvis appen ikke kender filmen.
    struct Item: Identifiable, Equatable {
        let recommendation: Recommendation
        let title: Title?
        /// Plakat og streamingtjeneste. `nil`, indtil TMDB har svaret (eller hvis filmen er ukendt).
        var media: TitleMedia? = nil

        var id: Int { recommendation.rank }
        var displayTitle: String { title?.title ?? "Movie #\(recommendation.movieID)" }
    }

    enum State: Equatable {
        case loading
        case empty                  // brugeren har ingen anbefalinger endnu
        case loaded([Item])
        case failed(String)
    }

    /// Så mange film vises. Modellen giver flere kandidater, så der er nok efter filtrering.
    static let shownCount = 10

    private(set) var state: State = .loading
    /// True mens "Get recommendations" kører.
    private(set) var isRecomputing = false
    /// True mens "Only my services" leder kandidaterne igennem.
    private(set) var isFiltering = false
    /// Fejl fra "Get recommendations". Vises over listen, så gamle anbefalinger stadig kan ses.
    var errorMessage: String?
    /// Fx "Only 3 of your top 50 movies are on your services right now."
    private(set) var filterNote: String?
    /// Brugerens streamingtjenester og "Only my services".
    private(set) var preferences = StreamingPreferences()

    /// Alle kandidater fra modellen, bedste først. Kun de første vises.
    private var candidates: [Item] = []
    /// Tælles op ved hver ny visning, så et langsomt, gammelt opslag ikke overskriver et nyere.
    private var generation = 0

    private let recommendationService: any RecommendationService
    private let movieDataService: any MovieDataService
    private let mediaService: any TitleMediaService
    private let preferencesService: any PreferencesService
    /// Hvad modellen lærer af. Styrer vejledningen, når der ingen anbefalinger er.
    let input: TasteInput
    /// Skærmens titel, fx "Star picks".
    let title: String

    init(
        recommendationService: any RecommendationService,
        movieDataService: any MovieDataService,
        mediaService: any TitleMediaService = MockTitleMediaService(),
        preferencesService: any PreferencesService = MockPreferencesService(),
        input: TasteInput = .likes,
        title: String = "For You"
    ) {
        self.recommendationService = recommendationService
        self.movieDataService = movieDataService
        self.mediaService = mediaService
        self.preferencesService = preferencesService
        self.input = input
        self.title = title
    }

    /// Fx "Like at least 5 movies in Swipe, then tap Get recommendations."
    var emptyHint: String { "\(input.requirementText), then tap Get recommendations." }

    var myServices: Set<StreamingService> { preferences.services }
    /// Kontakten "Only my services" vises kun, når brugeren har valgt tjenester.
    var canFilterByServices: Bool { !myServices.isEmpty }

    // MARK: - Handlinger

    /// Læser de seneste anbefalinger.
    func load() async {
        if case .loaded = state {} else { state = .loading }   // behold listen ved pull-to-refresh
        await loadPreferences()
        do {
            let recommendations = try await recommendationService.latestRecommendations()
            guard !recommendations.isEmpty else {
                candidates = []
                state = .empty
                return
            }
            // Slå alle film op på én gang i stedet for én ad gangen.
            let titles = try await movieDataService.titles(withIDs: recommendations.map(\.movieID))
            let titlesByID = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            candidates = recommendations.map { Item(recommendation: $0, title: titlesByID[$0.movieID]) }
            await showTopItems()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// "Get recommendations": beregner nye anbefalinger og viser dem bagefter.
    func recompute() async {
        guard !isRecomputing else { return }
        isRecomputing = true
        errorMessage = nil
        defer { isRecomputing = false }

        do {
            try await recommendationService.requestRecompute()
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Kontakten "Only my services".
    func setOnlyMyServices(_ isOn: Bool) async {
        guard isOn != preferences.onlyMyServices else { return }
        preferences.onlyMyServices = isOn
        try? await preferencesService.saveStreamingPreferences(preferences)
        await showTopItems()
    }

    /// Kaldes, når brugeren har ændret sine tjenester.
    func preferencesChanged() async {
        await loadPreferences()
        await showTopItems()
    }

    // MARK: - Visning

    private func loadPreferences() async {
        preferences = (try? await preferencesService.streamingPreferences()) ?? StreamingPreferences()
    }

    /// Vælger de film, der vises: de 10 bedste, eller de 10 bedste på brugerens tjenester.
    private func showTopItems() async {
        guard !candidates.isEmpty else { return }
        generation += 1
        let current = generation
        filterNote = nil
        isFiltering = false

        guard preferences.onlyMyServices, canFilterByServices else {
            let top = Array(candidates.prefix(Self.shownCount))
            state = .loaded(top)
            // Vis listen med det samme. Plakater og tjenester kommer bagefter.
            let withMedia = await attachMedia(to: top)
            guard current == generation else { return }
            state = .loaded(withMedia)
            return
        }

        // Kig kandidaterne igennem 10 ad gangen, til der er 10 på brugerens tjenester.
        isFiltering = true
        defer { if current == generation { isFiltering = false } }
        var matches: [Item] = []
        var index = 0
        while index < candidates.count, matches.count < Self.shownCount {
            let batch = Array(candidates[index..<min(index + Self.shownCount, candidates.count)])
            index += batch.count
            let withMedia = await attachMedia(to: batch)
            guard current == generation else { return }
            matches += withMedia.filter { $0.media?.provider(in: myServices) != nil }
        }
        let shown = Array(matches.prefix(Self.shownCount))
        if shown.count < Self.shownCount {
            filterNote = shown.isEmpty
                ? "None of your top \(candidates.count) movies are on your services right now."
                : "Only \(shown.count) of your top \(candidates.count) movies are on your services right now."
        }
        state = .loaded(shown)
    }

    /// Henter plakat og streamingtjeneste til filmene samtidig.
    private func attachMedia(to items: [Item]) async -> [Item] {
        let service = mediaService
        let lookups: [Task<TitleMedia?, Never>] = items.map { item in
            Task {
                guard let title = item.title else { return nil }
                return await service.media(for: title)
            }
        }
        var withMedia = items
        for index in withMedia.indices {
            withMedia[index].media = await lookups[index].value
        }
        return withMedia
    }

    // MARK: - Hjælpere

    private static func message(for error: Error) -> String {
        switch error as? RecommendationServiceError {
        case .tooFewLikes:
            return "\(TasteInput.likes.requirementText), so we know what you enjoy."
        case .tooFewRatings:
            return "\(TasteInput.starRatings.requirementText), so we know what you enjoy."
        case .notReady:
            return "The recommendation model couldn't be loaded. Please try again."
        case .unauthorized:
            return "Your session has expired. Sign out and in again."
        case .network:
            return "Couldn't load your answers. Please try again."
        case .unknown, nil:
            return "Something went wrong. Please try again."
        }
    }
}
