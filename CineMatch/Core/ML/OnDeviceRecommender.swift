//
//  OnDeviceRecommender.swift
//  CineMatch
//

import Foundation

/// Antons content-based model, kørt lokalt på telefonen.
///
/// Regner præcis som `Recommender.recommend()` i Python:
///   score = ½ · gennemsnit af similarity til dine likes + ½ · bedste enkelt-match
///   rangering = score + qualityBoost · quality   (popularitet bruges ikke)
/// Forskellen er, at similarity slås op i filen i stedet for at blive regnet ud.
/// Film, der ikke er blandt en likes nærmeste naboer, tæller som 0 for den like.
nonisolated struct OnDeviceRecommender: Sendable {
    nonisolated struct Result: Equatable, Sendable {
        let movieID: Int
        /// 0–1, samme som Antons "similarity". Vises som match-score.
        let score: Double
        /// Den af brugerens film, der ligner mest ("Because you liked …").
        let becauseMovieID: Int
        let shared: [SharedFeature]
        /// Hvor meget hver feature-type bidrager til `score`, største først.
        let breakdown: [FeatureContribution]
    }

    nonisolated struct SharedFeature: Equatable, Sendable {
        let label: String
        let values: [String]
    }

    nonisolated struct FeatureContribution: Equatable, Sendable {
        let label: String
        let value: Double
    }

    nonisolated enum LoadError: Error, Equatable {
        case unsupportedFormat(Int)
    }

    static let supportedFormatVersion = 1
    /// Samme grænse som Antons breakdown: mindre bidrag vises ikke.
    static let minimumContribution = 0.005
    /// Onboarding vælger blandt de så mange mest kendte film …
    static let onboardingPool = 2500
    /// … med mindst denne Letterboxd-rating.
    static let onboardingMinimumRating = 3.7

    let modelVersion: String
    private let file: ModelFile
    private let indexByID: [Int: Int]
    /// Normaliserede titler til søgning og til at undgå dubletter.
    private let titleKeys: [String]
    /// Normaliserede instruktør- og skuespillernavne, så man kan søge på dem.
    private let directorKeys: [String]
    private let castKeys: [String]

    init(file: ModelFile) throws {
        guard file.formatVersion == Self.supportedFormatVersion else {
            throw LoadError.unsupportedFormat(file.formatVersion)
        }
        self.file = file
        modelVersion = file.modelVersion
        var index: [Int: Int] = [:]
        for (position, film) in file.films.enumerated() where index[film.id] == nil {
            index[film.id] = position
        }
        indexByID = index
        titleKeys = file.films.map { Self.searchKey($0.title) }
        directorKeys = file.films.map { Self.searchKey($0.director) }
        castKeys = file.films.map { Self.searchKey($0.cast) }
    }

    // MARK: - Film

    var filmCount: Int { file.films.count }

    func film(id: Int) -> ModelFile.Film? {
        indexByID[id].map { file.films[$0] }
    }

    /// Film til onboarding-gitteret.
    var starterFilms: [ModelFile.Film] {
        file.starterIDs.compactMap(film(id:))
    }

    /// Kendte, godt bedømte spillefilm fordelt på genrer – til onboarding.
    /// Rækkefølge: den mest kendte fra hver genre, så den næstmest kendte fra hver genre osv.
    /// (Modellens egne `starterIDs` er mest nye Netflix-film, fordi popularitet = antal udgivelser.)
    func onboardingFilms(limit: Int = 150) -> [ModelFile.Film] {
        let candidates = file.films.prefix(Self.onboardingPool).filter { film in
            film.rating >= Self.onboardingMinimumRating
                && (film.runtime ?? 90) >= 60
                && !film.genres.contains("Documentary")
                && !film.genres.contains("Music")
        }
        var groups: [String: [ModelFile.Film]] = [:]
        var genreOrder: [String] = []
        for film in candidates {
            let genre = film.genres.first ?? ""
            if groups[genre] == nil { genreOrder.append(genre) }
            groups[genre, default: []].append(film)
        }
        // Store genrer først. Ved lige mange: den, der dukkede op først.
        genreOrder = genreOrder.enumerated()
            .sorted { (groups[$0.element]!.count, $1.offset) > (groups[$1.element]!.count, $0.offset) }
            .map(\.element)

        var result: [ModelFile.Film] = []
        var round = 0
        while result.count < limit {
            let films = genreOrder.compactMap { genre in groups[genre].flatMap { round < $0.count ? $0[round] : nil } }
            if films.isEmpty { break }
            result += films.prefix(limit - result.count)
            round += 1
        }
        return result.isEmpty ? starterFilms : result
    }

    /// Søger i titel, instruktør og skuespiller. Prioritet: titel der starter med søgningen,
    /// derefter titel der indeholder den, så instruktør, så skuespiller. Inden for hver gruppe
    /// efter filmens plads i kataloget (de mest kendte først). Hver film tælles kun én gang.
    func search(_ query: String, limit: Int = 20) -> [ModelFile.Film] {
        let key = Self.searchKey(query)
        guard !key.isEmpty else { return [] }
        var titlePrefix: [Int] = []
        var titleContains: [Int] = []
        var directorMatch: [Int] = []
        var castMatch: [Int] = []
        for position in file.films.indices {
            if titleKeys[position].hasPrefix(key) {
                titlePrefix.append(position)
            } else if titleKeys[position].contains(key) {
                titleContains.append(position)
            } else if directorKeys[position].contains(key) {
                directorMatch.append(position)
            } else if castKeys[position].contains(key) {
                castMatch.append(position)
            }
        }
        let ordered = titlePrefix + titleContains + directorMatch + castMatch
        return ordered.prefix(limit).map { file.films[$0] }
    }

    // MARK: - Anbefalinger

    /// Top `limit` film ud fra de film, brugeren kan lide.
    /// - Parameters:
    ///   - likedIDs: brugerens likes, vigtigste først. Ukendte id'er ignoreres.
    ///   - excludedIDs: film, der aldrig må anbefales (fx dislikes og allerede bedømte).
    func recommend(liked likedIDs: [Int], excluding excludedIDs: Set<Int> = [], limit: Int = 5) -> [Result] {
        var unique = Set<Int>()
        let liked = Array(
            likedIDs.compactMap { indexByID[$0] }.filter { unique.insert($0).inserted }.prefix(file.maxLiked)
        )
        guard !liked.isEmpty, limit > 0 else { return [] }
        let likedCount = Double(liked.count)

        // For hver kandidat: de likes, der har den som nabo (similarity + breakdown).
        var hitsByCandidate: [Int: [Hit]] = [:]
        for likedIndex in liked {
            for neighbor in file.neighbors[likedIndex] {
                hitsByCandidate[neighbor.i, default: []].append(Hit(likedIndex: likedIndex, neighbor: neighbor))
            }
        }

        let excluded = Set(liked).union(excludedIDs.compactMap { indexByID[$0] })
        let ranked = hitsByCandidate.compactMap { candidate, hits -> Ranked? in
            guard !excluded.contains(candidate) else { return nil }
            let total = hits.reduce(0) { $0 + $1.neighbor.s }
            let best = hits.map(\.neighbor.s).max() ?? 0
            let score = 0.5 * total / likedCount + 0.5 * best
            return Ranked(candidate: candidate, score: score, rank: score + file.qualityBoost * file.films[candidate].quality)
        }
        .sorted { ($0.rank, $1.candidate) > ($1.rank, $0.candidate) }

        // Kataloget har nogle titler to gange. Vis kun én af dem (som i Antons model).
        var seenTitles = Set(liked.map { titleKeys[$0] })
        var results: [Result] = []
        for entry in ranked where seenTitles.insert(titleKeys[entry.candidate]).inserted {
            results.append(makeResult(entry, hits: hitsByCandidate[entry.candidate] ?? [], likedCount: likedCount))
            if results.count == limit { break }
        }
        return results
    }

    /// Kort engelsk begrundelse, fx "Because you liked Se7en · Director: David Fincher · Themes: serial killer".
    func reason(for result: Result) -> String {
        var parts: [String] = []
        if let because = film(id: result.becauseMovieID) {
            parts.append("Because you liked \(because.title)")
        }
        // Instruktør, skuespillere og temaer siger mere end enkeltord fra beskrivelsen.
        let specific = result.shared.filter { $0.label != "Keywords" }
        let groups = (specific.isEmpty ? result.shared : specific).prefix(2)
        parts += groups.map { "\($0.label): \($0.values.prefix(2).joined(separator: ", "))" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hjælpere

    nonisolated private struct Hit {
        let likedIndex: Int
        let neighbor: ModelFile.Neighbor
    }

    nonisolated private struct Ranked {
        let candidate: Int
        let score: Double
        let rank: Double
    }

    private func makeResult(_ entry: Ranked, hits: [Hit], likedCount: Double) -> Result {
        let best = hits.max { $0.neighbor.s < $1.neighbor.s }

        // Breakdown kombineres som scoren: ½ gennemsnit over likes + ½ bedste match.
        var totals = [Double](repeating: 0, count: file.featureLabels.count)
        var bestParts = totals
        for hit in hits {
            for part in hit.neighbor.b {
                guard part.count == 2, let index = Int(exactly: part[0]), totals.indices.contains(index) else { continue }
                totals[index] += part[1]
                if hit.likedIndex == best?.likedIndex { bestParts[index] += part[1] }
            }
        }
        let breakdown = totals.indices
            .map { FeatureContribution(label: file.featureLabels[$0], value: 0.5 * totals[$0] / likedCount + 0.5 * bestParts[$0]) }
            .filter { $0.value >= Self.minimumContribution }
            .sorted { $0.value > $1.value }

        let shared = (best?.neighbor.x ?? []).compactMap { group -> SharedFeature? in
            guard let labelIndex = group.first, file.explainLabels.indices.contains(labelIndex) else { return nil }
            let values = group.dropFirst().compactMap { file.strings.indices.contains($0) ? file.strings[$0] : nil }
            return values.isEmpty ? nil : SharedFeature(label: file.explainLabels[labelIndex], values: values)
        }

        return Result(
            movieID: file.films[entry.candidate].id,
            score: entry.score,
            becauseMovieID: file.films[best?.likedIndex ?? entry.candidate].id,
            shared: shared,
            breakdown: breakdown
        )
    }

    /// "Amélie (2001)!" → "amelie 2001". Gør søgning uafhængig af store bogstaver, accenter og tegn.
    static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
