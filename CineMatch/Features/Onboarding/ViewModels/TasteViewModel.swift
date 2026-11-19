//
//  TasteViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// Brugeren går film igennem én ad gangen og giver hver en dom:
/// Horrible (1) · Bad (2) · Neutral (3) · Great (4) · Fantastic (5). Se `Verdict`.
///
/// "Haven't seen" springer filmen over. Den gemmes, så filmen først kommer igen efter
/// `Verdict.notSeenCooldown` – og så bagerst i bunken. Sete film bliver aldrig anbefalet.
@Observable
@MainActor
final class TasteViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Så mange Great/Fantastic skal der til, før modellen kender brugerens smag.
    static let minimumLikes = TasteInput.minimumCount
    /// Onboarding: så mange film (alle svar, også "Haven't seen") før "Your picks are ready".
    static let onboardingSwipes = 10

    private(set) var state: State = .loading
    /// Film, brugeren ikke har svaret på endnu. Den første vises på kortet.
    private(set) var queue: [Title] = []
    /// Brugerens dom pr. film-id.
    private(set) var verdicts: [Int: Verdict] = [:]
    /// Plakater pr. film-id fra TMDB. Mangler en film, viser kortet en pladsholder.
    private(set) var posterURLs: [Int: URL] = [:]
    /// Vises kort, hvis et svar ikke kunne gemmes.
    var errorMessage: String?

    /// Svarene i rækkefølge, så "Undo" kan gå et skridt tilbage.
    private var history: [TasteSignal] = []
    /// Filmene i `history`, så de kan lægges tilbage i køen.
    private var historyTitles: [Int: Title] = [:]

    private let movieDataService: any MovieDataService
    private let tasteSignalService: any TasteSignalService
    private let mediaService: any TitleMediaService
    /// Hvad den aktive model lærer af. Styrer, hvad der tæller i fremskridtet.
    let input: TasteInput

    init(
        movieDataService: any MovieDataService,
        tasteSignalService: any TasteSignalService,
        mediaService: any TitleMediaService = MockTitleMediaService(),
        input: TasteInput = .likes
    ) {
        self.movieDataService = movieDataService
        self.tasteSignalService = tasteSignalService
        self.mediaService = mediaService
        self.input = input
    }

    var current: Title? { queue.first }
    /// Great + Fantastic.
    var likeCount: Int { verdicts.values.filter(\.isPositive).count }
    /// Alle sete film (Horrible til Fantastic).
    var seenCount: Int { verdicts.values.filter(\.isSeen).count }
    var hasEnoughLikes: Bool { likeCount >= Self.minimumLikes }
    /// Alle svar, også "Haven't seen".
    var answeredCount: Int { verdicts.count }
    /// Onboarding er færdig: 10 svar, og nok Great/Fantastic til, at modellen kan anbefale.
    var isReadyForPicks: Bool { answeredCount >= Self.onboardingSwipes && hasEnoughLikes }
    /// Det antal svar, den aktive model kan bruge.
    var progressCount: Int { input == .likes ? likeCount : seenCount }
    var hasEnoughForRecommendations: Bool { progressCount >= TasteInput.minimumCount }
    var canUndo: Bool { !history.isEmpty }

    func count(of verdict: Verdict) -> Int { verdicts.values.filter { $0 == verdict }.count }

    // MARK: - Indlæsning

    func load() async {
        state = .loading
        do {
            // `async let` starter begge kald samtidig og venter på dem bagefter.
            async let loadedTitles = movieDataService.allTitles()
            async let loadedSignals = tasteSignalService.allSignals()
            let titles = try await loadedTitles
            let saved = try await loadedSignals
            verdicts = Dictionary(saved.map { ($0.movieID, $0.verdict) }, uniquingKeysWith: { newest, _ in newest })
            // Bedømte film vises ikke igen. Film sprunget over for længe siden kommer igen – efter de nye.
            let hidden = saved.hiddenFromSwipe()
            let visible = titles.filter { !hidden.contains($0.id) }
            queue = visible.filter { verdicts[$0.id] == nil } + visible.filter { verdicts[$0.id] != nil }
            history = []
            historyTitles = [:]
            state = .loaded
        } catch {
            AppLog.shared.error("Swipe: load failed", error)
            state = .failed("Couldn't load movies. Please try again.")
        }
    }

    /// Henter brugerens svar igen og fjerner film, der er bedømt et andet sted (fx i Search), fra bunken.
    /// Bevarer "Undo"-historikken. Kaldes, når Swipe-fanen vises.
    func syncAnswers() async {
        guard state == .loaded, let saved = try? await tasteSignalService.allSignals() else { return }
        verdicts = Dictionary(saved.map { ($0.movieID, $0.verdict) }, uniquingKeysWith: { newest, _ in newest })
        let hidden = saved.hiddenFromSwipe()
        queue.removeAll { hidden.contains($0.id) }
    }

    /// Henter plakaten til kortet, der vises nu, og de to næste, så de er klar, når brugeren swiper.
    func loadPosters() async {
        for title in queue.prefix(3) where posterURLs[title.id] == nil {
            if let url = await mediaService.media(for: title)?.posterURL {
                posterURLs[title.id] = url
            }
        }
    }

    // MARK: - Svar

    /// Giver filmen på kortet en dom og viser den næste.
    func rate(_ verdict: Verdict) async {
        guard let title = current else { return }
        let signal = TasteSignal(movieID: title.id, verdict: verdict)

        // Opdatér skærmen med det samme ("optimistisk"), og ret tilbage, hvis det ikke kan gemmes.
        queue.removeFirst()
        verdicts[title.id] = verdict
        history.append(signal)
        historyTitles[title.id] = title
        errorMessage = nil

        do {
            try await tasteSignalService.save(signal)
        } catch {
            AppLog.shared.error("Swipe: save answer failed", error)
            verdicts[title.id] = nil
            history.removeAll { $0.movieID == title.id }
            historyTitles[title.id] = nil
            queue.insert(title, at: 0)
            errorMessage = "Couldn't save your answer for \(title.title). Please try again."
        }
    }

    /// Går et svar tilbage og viser filmen igen.
    func undo() async {
        guard let last = history.popLast(), let title = historyTitles.removeValue(forKey: last.movieID) else { return }
        queue.insert(title, at: 0)
        verdicts[title.id] = nil
        errorMessage = nil
        do {
            try await tasteSignalService.deleteSignal(movieID: title.id)
        } catch {
            AppLog.shared.error("Swipe: undo failed", error)
            verdicts[title.id] = last.verdict
            queue.removeAll { $0.id == title.id }
            history.append(last)
            historyTitles[title.id] = title
            errorMessage = "Couldn't undo. Please try again."
        }
    }
}
