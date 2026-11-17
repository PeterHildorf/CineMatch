//
//  SearchViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// "Search": brugeren søger film frem i Antons on-device-katalog og liker dem, han kan lide.
/// Likes gemmes i samme bunke som Swipe (Antons pipeline), så de tæller med i "Swipe picks".
@Observable
@MainActor
final class SearchViewModel {
    /// Søgeteksten. Bindes til søgefeltet i viewet.
    var query: String = ""
    /// De fundne film, bedste match først. Tom ved tom søgning.
    private(set) var results: [Title] = []
    /// Forslag der vises, når søgefeltet er tomt: kendte film fordelt på genrer, så man kan browse.
    private(set) var suggestions: [Title] = []
    /// Valgt genre-chip i browse-visningen. `nil` = alle.
    var selectedGenre: String?
    /// Film-id'er, brugeren har liket (fra swipe/Anton-bunken). Styrer like-knappens udseende.
    private(set) var likedIDs: Set<Int> = []
    /// Plakater pr. film-id fra TMDB. Mangler en film, vises en pladsholder.
    private(set) var posterURLs: [Int: URL] = [:]
    /// True mens en søgning kører (efter kort forsinkelse).
    private(set) var isSearching = false
    /// Vises kort, hvis et like ikke kunne gemmes, eller søgningen fejlede.
    var errorMessage: String?

    private let movieDataService: any MovieDataService
    private let signalService: any TasteSignalService
    private let mediaService: any TitleMediaService

    init(
        movieDataService: any MovieDataService,
        signalService: any TasteSignalService,
        mediaService: any TitleMediaService = MockTitleMediaService()
    ) {
        self.movieDataService = movieDataService
        self.signalService = signalService
        self.mediaService = mediaService
    }

    var likeCount: Int { likedIDs.count }
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func isLiked(_ title: Title) -> Bool { likedIDs.contains(title.id) }

    /// Genrerne i forslagene, mest hyppige først. Vises som chips man kan filtrere på.
    var genres: [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for genre in suggestions.flatMap(\.genres) {
            if counts[genre] == nil { order.append(genre) }
            counts[genre, default: 0] += 1
        }
        return order.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    /// Forslagene der vises nu: alle, eller kun dem i den valgte genre.
    var browseResults: [Title] {
        guard let selectedGenre else { return suggestions }
        return suggestions.filter { $0.genres.contains(selectedGenre) }
    }

    // MARK: - Indlæsning

    /// Henter brugerens eksisterende likes, så film han allerede har liket (fx i Swipe) vises som liket.
    func loadLikes() async {
        guard let signals = try? await signalService.allSignals() else { return }
        likedIDs = Set(signals.filter { $0.kind == .like }.map(\.movieID))
    }

    /// Henter kendte film til browse-visningen (vises, når der ikke er søgt endnu).
    func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        suggestions = (try? await movieDataService.allTitles()) ?? []
    }

    /// Søger med kort forsinkelse ("debounce"). Kaldes af viewet, hver gang teksten ændrer sig;
    /// en ny søgning afbryder den forrige, så vi kun rammer modellen, når brugeren holder pause.
    func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(250))   // vent til brugeren holder pause
            let found = try await movieDataService.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch is CancellationError {
            // Brugeren skrev videre – den nye søgning overtager.
        } catch {
            errorMessage = "Couldn't search right now. Please try again."
        }
    }

    /// Henter plakaten til en række, når den vises.
    func loadPoster(for title: Title) async {
        guard posterURLs[title.id] == nil,
              let url = await mediaService.media(for: title)?.posterURL else { return }
        posterURLs[title.id] = url
    }

    // MARK: - Like

    /// Liker filmen, eller fjerner et like igen. Opdaterer skærmen med det samme og retter tilbage ved fejl.
    func toggleLike(_ title: Title) async {
        errorMessage = nil
        if likedIDs.contains(title.id) {
            likedIDs.remove(title.id)
            do {
                try await signalService.deleteSignal(movieID: title.id)
            } catch {
                likedIDs.insert(title.id)
                errorMessage = "Couldn't remove your like of \(title.title). Please try again."
            }
        } else {
            likedIDs.insert(title.id)
            do {
                try await signalService.save(TasteSignal(movieID: title.id, kind: .like))
            } catch {
                likedIDs.remove(title.id)
                errorMessage = "Couldn't save your like of \(title.title). Please try again."
            }
        }
    }
}
