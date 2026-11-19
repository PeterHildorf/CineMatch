//
//  SearchViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// "Search": brugeren søger film frem i Antons on-device-katalog og bedømmer dem, han har set,
/// med samme skala som Swipe (Horrible 1 · Bad 2 · Neutral 3 · Great 4 · Fantastic 5).
/// Dommene gemmes i samme bunke som Swipe (pipeline `swipe`), så de ændrer Today.
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
    /// Brugerens dom pr. film-id. Styrer knappens udseende.
    private(set) var verdicts: [Int: Verdict] = [:]
    /// Film, der allerede var bedømt (set), da skærmen blev indlæst. De skjules i browse-visningen,
    /// men kan stadig søges frem, hvis man har glemt, at man har bedømt dem.
    /// Bevidst et øjebliksbillede: en film, man bedømmer nu, bliver stående, så man kan se og fortryde
    /// dommen. Den forsvinder først fra browse, næste gang skærmen indlæses.
    private(set) var hiddenFromBrowse: Set<Int> = []
    /// Plakater pr. film-id fra TMDB. Mangler en film, vises en pladsholder.
    private(set) var posterURLs: [Int: URL] = [:]
    /// True mens en søgning kører (efter kort forsinkelse).
    private(set) var isSearching = false
    /// Vises kort, hvis en dom ikke kunne gemmes, eller søgningen fejlede.
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

    /// Sete film, brugeren har bedømt her.
    var ratedCount: Int { verdicts.values.filter(\.isSeen).count }
    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func verdict(for title: Title) -> Verdict? { verdicts[title.id] }

    /// Forslagene minus de film, brugeren allerede har bedømt.
    private var unratedSuggestions: [Title] {
        suggestions.filter { !hiddenFromBrowse.contains($0.id) }
    }

    /// Genrerne i forslagene, mest hyppige først. Vises som chips man kan filtrere på.
    var genres: [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for genre in unratedSuggestions.flatMap(\.genres) {
            if counts[genre] == nil { order.append(genre) }
            counts[genre, default: 0] += 1
        }
        return order.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    /// Forslagene der vises nu: alle ubedømte, eller kun dem i den valgte genre.
    /// Søgeresultater (`results`) filtreres IKKE – der vises bedømte film med deres dom.
    var browseResults: [Title] {
        guard let selectedGenre else { return unratedSuggestions }
        return unratedSuggestions.filter { $0.genres.contains(selectedGenre) }
    }

    // MARK: - Indlæsning

    /// Henter brugerens eksisterende domme, så knappen viser dem.
    func loadVerdicts() async {
        guard let signals = try? await signalService.allSignals() else { return }
        verdicts = Dictionary(signals.map { ($0.movieID, $0.verdict) }, uniquingKeysWith: { newest, _ in newest })
        // Kun sete film skjules; "Haven't seen" fra Swipe kan stadig bedømmes her.
        hiddenFromBrowse = Set(verdicts.filter { $0.value.isSeen }.keys)
        if let selectedGenre, !genres.contains(selectedGenre) { self.selectedGenre = nil }
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
            AppLog.shared.error("Search: search failed", error)
            errorMessage = "Couldn't search right now. Please try again."
        }
    }

    /// Henter plakaten til en række, når den vises.
    func loadPoster(for title: Title) async {
        guard posterURLs[title.id] == nil,
              let url = await mediaService.media(for: title)?.posterURL else { return }
        posterURLs[title.id] = url
    }

    // MARK: - Dom

    /// Gemmer brugerens dom. Opdaterer skærmen med det samme og retter tilbage ved fejl.
    func rate(_ title: Title, _ verdict: Verdict) async {
        errorMessage = nil
        let previous = verdicts[title.id]
        verdicts[title.id] = verdict
        do {
            try await signalService.save(TasteSignal(movieID: title.id, verdict: verdict))
        } catch {
            AppLog.shared.error("Search: save rating failed", error)
            verdicts[title.id] = previous
            errorMessage = "Couldn't save your rating of \(title.title). Please try again."
        }
    }

    /// Fjerner brugerens dom igen.
    func removeRating(_ title: Title) async {
        errorMessage = nil
        guard let previous = verdicts.removeValue(forKey: title.id) else { return }
        do {
            try await signalService.deleteSignal(movieID: title.id)
        } catch {
            AppLog.shared.error("Search: remove rating failed", error)
            verdicts[title.id] = previous
            errorMessage = "Couldn't remove your rating of \(title.title). Please try again."
        }
    }
}
