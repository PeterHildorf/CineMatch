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

        /// Film-id, ikke rank: så SwiftUI kan animere, når en film fjernes og en ny rykker op.
        var id: Int { recommendation.movieID }
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
    /// Plakater og tjenester, der allerede er slået op (også `nil` = "findes ikke").
    /// Så en erstatning efter "Seen it" ikke slår hele listen op igen.
    private var mediaCache: [Int: TitleMedia?] = [:]
    /// Batchet, de viste anbefalinger kommer fra. Visninger og "Seen it" logges under det.
    private var currentBatch: RecommendationBatch?
    /// Film, der allerede er logget som vist i `currentBatch` (første visning tæller).
    private var loggedImpressions: Set<Int> = []

    private let recommendationService: any RecommendationService
    private let movieDataService: any MovieDataService
    private let mediaService: any TitleMediaService
    private let preferencesService: any PreferencesService
    /// Hvor "Seen it" gemmes. Skal være den samme, som modellen læser fra, så feedback tæller som input.
    /// `nil` = ingen "Seen it" (fx stjernemodellen, indtil vi ved, hvordan like/dislike skal oversættes).
    private let signalService: (any TasteSignalService)?
    /// Måler præcisionen: hvad blev vist, og hvad sagde brugeren til det.
    private let eventLogger: any RecommendationEventLogger
    /// Hvad modellen lærer af. Styrer vejledningen, når der ingen anbefalinger er.
    let input: TasteInput
    /// Skærmens titel, fx "Star picks".
    let title: String

    init(
        recommendationService: any RecommendationService,
        movieDataService: any MovieDataService,
        mediaService: any TitleMediaService = MockTitleMediaService(),
        preferencesService: any PreferencesService = MockPreferencesService(),
        signalService: (any TasteSignalService)? = nil,
        eventLogger: any RecommendationEventLogger = MockRecommendationEventLogger(),
        input: TasteInput = .likes,
        title: String = "For You"
    ) {
        self.recommendationService = recommendationService
        self.movieDataService = movieDataService
        self.mediaService = mediaService
        self.preferencesService = preferencesService
        self.signalService = signalService
        self.eventLogger = eventLogger
        self.input = input
        self.title = title
    }

    /// Fx "Like at least 5 movies in Swipe, then tap Get recommendations."
    var emptyHint: String { "\(input.requirementText), then tap Get recommendations." }

    var myServices: Set<StreamingService> { preferences.services }
    /// Kontakten "Only my services" vises kun, når brugeren har valgt tjenester.
    var canFilterByServices: Bool { !myServices.isEmpty }
    /// Knappen "Seen it" vises kun, hvis svaret kan gemmes.
    var canMarkSeen: Bool { signalService != nil }

    // MARK: - Handlinger

    /// Læser de seneste anbefalinger.
    func load() async {
        if case .loaded = state {} else { state = .loading }   // behold listen ved pull-to-refresh
        await loadPreferences()
        do {
            let recommendations = try await recommendationService.latestRecommendations()
            setBatch(await recommendationService.latestBatch())
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
            AppLog.shared.error("\(title): load failed", error)
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
            AppLog.shared.error("\(title): recompute failed", error)
            errorMessage = Self.message(for: error)
        }
    }

    /// "Seen it" → like eller dislike. Filmen forsvinder med det samme, og næste kandidat rykker op.
    /// Svaret gemmes som modellens input (`source = .feedback`), så næste "Get recommendations" lærer af det.
    /// Løber kandidaterne tør, beregnes nye anbefalinger.
    func markSeen(_ item: Item, liked: Bool) async {
        guard let signalService,
              let index = candidates.firstIndex(where: { $0.id == item.id }) else { return }
        errorMessage = nil

        // Fjern først, så listen reagerer med det samme. Lægges tilbage, hvis gemningen fejler.
        let removed = candidates.remove(at: index)
        await showTopItems()

        let signal = TasteSignal(movieID: item.recommendation.movieID, kind: liked ? .like : .dislike, source: .feedback)
        do {
            try await signalService.save(signal)
        } catch {
            AppLog.shared.error("\(title): Seen it failed for movie \(signal.movieID)", error)
            candidates.insert(removed, at: min(index, candidates.count))
            errorMessage = "Couldn't save your answer. Please try again."
            await showTopItems()
            return
        }
        if let currentBatch {
            eventLogger.log(.feedback(batchID: currentBatch.id, movieID: signal.movieID, outcome: liked ? .seenLiked : .seenDisliked))
        }

        if candidates.count < Self.shownCount {
            await recompute()
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
        guard !candidates.isEmpty else {
            // Sker kun, hvis "Seen it" har fjernet den sidste kandidat.
            if case .loaded = state { show([]) }
            return
        }
        generation += 1
        let current = generation
        filterNote = nil
        isFiltering = false

        guard preferences.onlyMyServices, canFilterByServices else {
            let top = Array(candidates.prefix(Self.shownCount))
            show(top)
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
        show(shown)
    }

    /// Viser listen og logger de film, der ikke er logget som vist i dette batch før.
    private func show(_ items: [Item]) {
        state = .loaded(items)
        guard let currentBatch else { return }
        let new = items.enumerated()
            .filter { !loggedImpressions.contains($0.element.id) }
            .map { position, item in
                RecommendationImpression(
                    movieID: item.recommendation.movieID,
                    rank: item.recommendation.rank,
                    score: item.recommendation.score,
                    shownPosition: position + 1
                )
            }
        guard !new.isEmpty else { return }
        // Batchet logges først sammen med sin første visning, så batches, ingen så, ikke tæller.
        if loggedImpressions.isEmpty {
            eventLogger.log(.batch(currentBatch))
        }
        loggedImpressions.formUnion(new.map(\.movieID))
        eventLogger.log(.impressions(batchID: currentBatch.id, new))
    }

    /// Skifter batch, når modellen har regnet nye anbefalinger.
    private func setBatch(_ batch: RecommendationBatch?) {
        guard batch?.id != currentBatch?.id else { return }
        currentBatch = batch
        loggedImpressions = []
    }

    /// Henter plakat og streamingtjeneste til filmene samtidig. Film, der er slået op før, hentes fra cachen.
    private func attachMedia(to items: [Item]) async -> [Item] {
        let service = mediaService
        let cache = mediaCache
        let lookups: [Task<TitleMedia?, Never>?] = items.map { item in
            guard let title = item.title, cache[title.id] == nil else { return nil }
            return Task { await service.media(for: title) }
        }
        var withMedia = items
        for index in withMedia.indices {
            guard let title = withMedia[index].title else { continue }
            if let lookup = lookups[index] {
                let media = await lookup.value
                mediaCache[title.id] = .some(media)
                withMedia[index].media = media
            } else {
                withMedia[index].media = cache[title.id] ?? nil
            }
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
