//
//  TasteViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// Brugeren går film igennem én ad gangen og svarer Like, Dislike, ½–5 stjerner eller "Haven't seen".
/// Antons model lærer af likes, Mikkels af stjerner (`input`). Film med et svar bliver aldrig anbefalet.
@Observable
@MainActor
final class TasteViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Så mange likes (eller stjerner) skal der til, før modellen kender brugerens smag.
    static let minimumLikes = TasteInput.minimumCount

    private(set) var state: State = .loading
    /// Film, brugeren ikke har svaret på endnu. Den første vises på kortet.
    private(set) var queue: [Title] = []
    /// Brugerens svar pr. film-id.
    private(set) var signals: [Int: TasteSignal.Kind] = [:]
    /// Brugerens stjerner pr. film-id (kun film, han har givet stjerner).
    private(set) var ratings: [Int: Double] = [:]
    /// Plakater pr. film-id fra TMDB. Mangler en film, viser kortet en pladsholder.
    private(set) var posterURLs: [Int: URL] = [:]
    /// Vises kort, hvis et svar ikke kunne gemmes.
    var errorMessage: String?

    /// Svarene i rækkefølge, så "Undo" kan gå et skridt tilbage. `signal == nil` betyder "Haven't seen".
    private var history: [(title: Title, signal: TasteSignal?)] = []

    private let movieDataService: any MovieDataService
    private let tasteSignalService: any TasteSignalService
    private let mediaService: any TitleMediaService
    /// Hvad den aktive model lærer af: likes (Anton) eller stjerner (Mikkel).
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
    var likeCount: Int { signals.values.filter { $0 == .like }.count }
    var dislikeCount: Int { signals.values.filter { $0 == .dislike }.count }
    var hasEnoughLikes: Bool { likeCount >= Self.minimumLikes }
    var ratedCount: Int { ratings.count }
    /// Det antal svar, den aktive model kan bruge.
    var progressCount: Int { input == .likes ? likeCount : ratedCount }
    var hasEnoughForRecommendations: Bool { progressCount >= TasteInput.minimumCount }
    var canUndo: Bool { !history.isEmpty }

    // MARK: - Indlæsning

    func load() async {
        state = .loading
        do {
            // `async let` starter begge kald samtidig og venter på dem bagefter.
            async let loadedTitles = movieDataService.allTitles()
            async let loadedSignals = tasteSignalService.allSignals()
            let titles = try await loadedTitles
            let saved = try await loadedSignals
            signals = Dictionary(saved.map { ($0.movieID, $0.kind) }, uniquingKeysWith: { newest, _ in newest })
            ratings = Dictionary(
                saved.compactMap { signal in signal.rating.map { (signal.movieID, $0) } },
                uniquingKeysWith: { newest, _ in newest }
            )
            // Film, brugeren allerede har svaret på, vises ikke igen.
            queue = titles.filter { signals[$0.id] == nil }
            history = []
            state = .loaded
        } catch {
            AppLog.shared.error("Swipe: load failed", error)
            state = .failed("Couldn't load movies. Please try again.")
        }
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

    func like() async { await answer(TasteSignal(movieID: current?.id ?? 0, kind: .like)) }

    func dislike() async { await answer(TasteSignal(movieID: current?.id ?? 0, kind: .dislike)) }

    /// ½–5 stjerner. Gemmes som stjerner, og like/dislike udledes (3½+ = like, 2 og under = dislike).
    func rate(_ stars: Double) async {
        let clamped = min(max((stars * 2).rounded() / 2, 0.5), 5)
        await answer(TasteSignal(movieID: current?.id ?? 0, kind: TasteSignal.kind(forStars: clamped), rating: clamped))
    }

    /// "Haven't seen it": filmen springes over og gemmes ikke.
    func skip() {
        guard let title = current else { return }
        queue.removeFirst()
        history.append((title, nil))
        errorMessage = nil
    }

    /// Går et svar tilbage og viser filmen igen.
    func undo() async {
        guard let last = history.popLast() else { return }
        queue.insert(last.title, at: 0)
        errorMessage = nil
        guard let signal = last.signal else { return }

        signals[last.title.id] = nil
        ratings[last.title.id] = nil
        do {
            try await tasteSignalService.deleteSignal(movieID: last.title.id)
        } catch {
            AppLog.shared.error("Swipe: undo failed", error)
            signals[last.title.id] = signal.kind
            ratings[last.title.id] = signal.rating
            queue.removeAll { $0.id == last.title.id }
            history.append(last)
            errorMessage = "Couldn't undo. Please try again."
        }
    }

    private func answer(_ signal: TasteSignal) async {
        guard let title = current, title.id == signal.movieID else { return }

        // Opdatér skærmen med det samme ("optimistisk"), og ret tilbage, hvis det ikke kan gemmes.
        queue.removeFirst()
        signals[title.id] = signal.kind
        ratings[title.id] = signal.rating
        history.append((title, signal))
        errorMessage = nil

        do {
            try await tasteSignalService.save(signal)
        } catch {
            AppLog.shared.error("Swipe: save answer failed", error)
            signals[title.id] = nil
            ratings[title.id] = nil
            history.removeAll { $0.title.id == title.id }
            queue.insert(title, at: 0)
            errorMessage = "Couldn't save your answer for \(title.title). Please try again."
        }
    }
}
