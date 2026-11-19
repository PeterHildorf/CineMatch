//
//  RecommendationsViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// Henter top 10 fra én model og kobler dem sammen med filmdata.
///
/// Med en `DailyPickStore` (fanen Recommendations) er den første film "Tonight's pick": én film om dagen.
/// Har brugeren allerede set den, rykker den næste anbefaling op, så der altid er en film til i aften.
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
    /// Så mange film efter "Show more". Antons model giver 20 kandidater (og flere, når der filtreres).
    static let maxShownCount = 20
    /// Antal film i listen lige nu: `shownCount`, eller `maxShownCount` efter "Show more".
    /// Dagens pick kommer oven i, så Today viser pick + top 10.
    private(set) var listLimit = shownCount
    /// True, hvis der er flere kandidater, end listen viser, og "Show more" ikke er brugt endnu.
    private(set) var canShowMore = false

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
    /// Dagens pick. `nil` = almindelig liste uden dagens pick.
    private let dailyPicks: DailyPickStore?
    /// Beregn selv anbefalinger, når brugerens svar har ændret sig (ingen "Get recommendations"-knap).
    let autoRecompute: Bool
    /// "Nu". Kan sættes i tests.
    var now: () -> Date = { .now }
    /// Brugerens svar, da anbefalingerne sidst blev beregnet. Ændrer de sig, beregnes nye.
    private var computedInput: Set<String>?

    /// Film-id for dagens pick (første film i listen). `nil` = ingen kandidater.
    private(set) var dailyPickID: Int?
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
        dailyPicks: DailyPickStore? = nil,
        autoRecompute: Bool = false,
        input: TasteInput = .likes,
        title: String = "For You"
    ) {
        self.dailyPicks = dailyPicks
        self.autoRecompute = autoRecompute
        self.recommendationService = recommendationService
        self.movieDataService = movieDataService
        self.mediaService = mediaService
        self.preferencesService = preferencesService
        self.signalService = signalService
        self.eventLogger = eventLogger
        self.input = input
        self.title = title
    }

    /// Fx "Rate at least 5 movies Great or Fantastic in Swipe, then tap Get recommendations."
    var emptyHint: String {
        autoRecompute
            ? "\(input.requirementText) in Swipe. Your picks show up here."
            : "\(input.requirementText), then tap Get recommendations."
    }

    /// Dage i træk med en dom over en pick.
    var streak: Int { dailyPicks?.streak(on: now()) ?? 0 }
    var hasDailyPick: Bool { dailyPicks != nil }

    var myServices: Set<StreamingService> { preferences.services }
    /// Kontakten "Only my services" vises kun, når brugeren har valgt tjenester.
    var canFilterByServices: Bool { !myServices.isEmpty }
    /// Knappen "Seen it" vises kun, hvis svaret kan gemmes.
    var canMarkSeen: Bool { signalService != nil }

    // MARK: - Handlinger

    /// Kaldes, når skærmen vises. Med `autoRecompute` beregnes nye anbefalinger, hvis brugerens svar
    /// har ændret sig siden sidst (fx flere film i Swipe). Ellers vises de seneste.
    func refresh() async {
        guard autoRecompute, let signalService else {
            await load()
            return
        }
        let input = (try? await signalService.allSignals()).map { Set($0.map { "\($0.movieID):\($0.score)" }) }
        guard let input else {
            await load()
            return
        }
        if input == computedInput {
            // "Start fresh" intentionally leaves an empty profile and no result.
            // An unchanged nonempty profile may have lost its result after a
            // session/cache reset or failed recompute; its fingerprint alone
            // does not establish that there is still a result to display.
            if input.isEmpty {
                await load()
                return
            }
            if let cached = try? await recommendationService.latestRecommendations(), !cached.isEmpty {
                await load()
                return
            }
        }
        await recompute()
        if errorMessage == nil { computedInput = input }
    }

    /// Læser de seneste anbefalinger.
    func load() async {
        if case .loaded = state {} else { state = .loading }   // behold listen ved pull-to-refresh
        await loadPreferences()
        do {
            let recommendations = try await recommendationService.latestRecommendations()
            setBatch(await recommendationService.latestBatch())
            guard !recommendations.isEmpty else {
                candidates = []
                dailyPickID = nil
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
            // Første gang (ingen liste endnu): vis tom-skærmen med fejlen i stedet for en evig spinner.
            if case .loading = state { state = .empty }
        }
    }

    /// "Seen it" → Horrible, Bad, Great eller Fantastic. Filmen forsvinder med det samme, og næste kandidat rykker op.
    /// Dommen gemmes som modellens input (`source = .feedback`), så næste beregning lærer af den.
    /// Er det dagens pick, tæller dagen i streaken, og næste kandidat bliver dagens pick med det samme.
    /// Modellen regner dommen med næste gang, fanen åbnes (`refresh`), eller når kandidaterne løber tør.
    func markSeen(_ item: Item, verdict: Verdict) async {
        guard verdict.isSeen, let signalService,
              let index = candidates.firstIndex(where: { $0.id == item.id }) else { return }
        errorMessage = nil
        let wasDailyPick = item.id == dailyPickID

        // Fjern først, så listen reagerer med det samme. Lægges tilbage, hvis gemningen fejler.
        let removed = candidates.remove(at: index)
        if wasDailyPick { dailyPicks?.markAnswered(movieID: item.id, on: now()) }
        await showTopItems()

        let signal = TasteSignal(movieID: item.recommendation.movieID, verdict: verdict, source: .feedback)
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
            eventLogger.log(.feedback(batchID: currentBatch.id, movieID: signal.movieID, verdict: verdict))
        }

        if candidates.count < Self.shownCount {
            await recompute()
        }
    }

    /// "Show more": viser op til `maxShownCount` film.
    func showMore() async {
        guard listLimit < Self.maxShownCount else { return }
        listLimit = Self.maxShownCount
        await showTopItems()
    }

    /// "Another pick": dagens pick springes over, og den næste bedste bliver dagens pick.
    func anotherDailyPick() async {
        guard let dailyPicks, let dailyPickID else { return }
        dailyPicks.pass(movieID: dailyPickID, on: now())
        await showTopItems()
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

    /// "Start fresh" i Profile: brugerens svar er slettet, så de gamle anbefalinger skal væk.
    /// Viser tom-skærmen ("Rate at least 5 …") uden fejl, indtil brugeren har bedømt nok igen.
    func startOver() async {
        generation += 1                 // et opslag, der kører nu, må ikke vise den gamle liste
        await recommendationService.clearRecommendations()
        candidates = []
        dailyPickID = nil
        listLimit = Self.shownCount
        canShowMore = false
        errorMessage = nil
        filterNote = nil
        isFiltering = false
        setBatch(nil)
        computedInput = []              // "beregnet ud fra ingen svar" → næste `refresh` regner først, når der er nye
        state = .empty
    }

    // MARK: - Visning

    private func loadPreferences() async {
        preferences = (try? await preferencesService.streamingPreferences()) ?? StreamingPreferences()
    }

    /// Vælger de film, der vises: de 10 bedste, eller de 10 bedste på brugerens tjenester.
    private func showTopItems() async {
        guard !candidates.isEmpty else {
            // Sker kun, hvis "Seen it" har fjernet den sidste kandidat.
            dailyPickID = nil
            canShowMore = false
            if case .loaded = state { show([]) }
            return
        }
        generation += 1
        let current = generation
        filterNote = nil
        isFiltering = false
        // Dagens pick vises over listen og tæller ikke med i top 10.
        let target = listLimit + (dailyPicks == nil ? 0 : 1)

        guard preferences.onlyMyServices, canFilterByServices else {
            let top = Array(dailyPickFirst(candidates).prefix(target))
            canShowMore = listLimit < Self.maxShownCount && candidates.count > top.count
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
        while index < candidates.count, matches.count < target {
            let batch = Array(candidates[index..<min(index + Self.shownCount, candidates.count)])
            index += batch.count
            let withMedia = await attachMedia(to: batch)
            guard current == generation else { return }
            matches += withMedia.filter { $0.media?.provider(in: myServices) != nil }
        }
        let shown = Array(dailyPickFirst(matches).prefix(target))
        canShowMore = listLimit < Self.maxShownCount && (matches.count > shown.count || index < candidates.count)
        if shown.count < target {
            filterNote = shown.isEmpty
                ? "None of your top \(candidates.count) movies are on your services right now."
                : "Only \(shown.count) of your top \(candidates.count) movies are on your services right now."
        }
        show(shown)
    }

    /// Vælger dagens pick blandt `items` og lægger den forrest. Uden `DailyPickStore` uændret.
    private func dailyPickFirst(_ items: [Item]) -> [Item] {
        guard let dailyPicks else { return items }
        dailyPickID = dailyPicks.pick(from: items.map(\.id), on: now())
        guard let dailyPickID, let index = items.firstIndex(where: { $0.id == dailyPickID }) else { return items }
        var ordered = items
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
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
            return "\(TasteInput.likes.requirementText) in Swipe, so we know what you enjoy."
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
