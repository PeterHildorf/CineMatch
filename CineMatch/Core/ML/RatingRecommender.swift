//
//  RatingRecommender.swift
//  CineMatch
//

import Foundation

/// Antons nye model: forudsiger brugerens dom (1–5) for hver film og anbefaler dem med højest forudsigelse.
///
/// Input er ALLE sete film med deres tal (Horrible 1 … Fantastic 5) – også dislikes.
///
/// ⚠️ Formlen er udledt af filens felter, ikke af Antons kode. Skal bekræftes af Anton:
///   brugerens gennemsnit  m   = (Σ domme + personalFromRatings · globalMean) / (antal + personalFromRatings)
///   afvigelse for set film r  = dom − m
///   pr. kilde k (letterboxd, movielens, tag), over kandidatens naboer j, som brugeren har set:
///                         d_k = Σ s_ij · r_j / (Σ s_ij + shrink)        (0, hvis ingen)
///   forudsigelse          = m + intercept + w_filmDeviation · filmDeviation_i + Σ w_k · d_k
/// Al regning ligger i `predict(_:for:)`, så den er nem at rette.
nonisolated struct RatingRecommender: Sendable {
    nonisolated struct Rating: Equatable, Sendable {
        let movieID: Int
        /// 1–5 fra `Verdict`.
        let score: Double
    }

    nonisolated struct Result: Equatable, Sendable {
        let movieID: Int
        /// Forudsagt dom (ca. 1–5).
        let predicted: Double
        /// Den sete film, der trækker mest op ("Because you liked …"). `nil`, hvis ingen gør.
        let becauseMovieID: Int?
    }

    nonisolated enum LoadError: Error, Equatable {
        case unsupportedFormat(Int)
        /// Nabolisterne passer ikke til antallet af film.
        case inconsistentFile
    }

    static let supportedFormatVersions: Set<Int> = [2]

    let modelVersion: String
    /// Kun tallene fra filen – nabolisterne gemmes kompakt i `sources`, så de ikke ligger dobbelt i hukommelsen.
    private let films: [RatingModelFile.Film]
    private let weights: RatingModelFile.Weights
    private let shrink: Double
    private let globalMean: Double
    private let personalFromRatings: Double
    private let indexByID: [Int: Int]
    /// Normaliserede titler, så kataloget ikke viser samme titel to gange.
    private let titleKeys: [String]
    /// Naboer pr. kilde i samme rækkefølge som `sourceWeights`.
    private let sources: [[[Neighbor]]]
    private let sourceWeights: [Double]

    init(file: RatingModelFile) throws {
        guard Self.supportedFormatVersions.contains(file.ratingFormatVersion) else {
            throw LoadError.unsupportedFormat(file.ratingFormatVersion)
        }
        let raw = [file.letterboxdNeighbors, file.movielensNeighbors, file.tagNeighbors]
        guard raw.allSatisfy({ $0.count == file.films.count }) else {
            throw LoadError.inconsistentFile
        }
        films = file.films
        weights = file.weights
        shrink = file.shrink
        globalMean = file.globalMean
        personalFromRatings = file.personalFromRatings
        modelVersion = file.modelVersion ?? "rating-v\(file.ratingFormatVersion)"
        var index: [Int: Int] = [:]
        for (position, film) in file.films.enumerated() where index[film.id] == nil {
            index[film.id] = position
        }
        indexByID = index
        titleKeys = file.films.map { OnDeviceRecommender.searchKey($0.title) }
        let filmCount = file.films.count
        sources = raw.map { lists in
            lists.map { list in
                list.compactMap { pair -> Neighbor? in
                    guard pair.count == 2, let i = Int(exactly: pair[0]), i >= 0, i < filmCount else { return nil }
                    return Neighbor(index: i, similarity: pair[1])
                }
            }
        }
        sourceWeights = [file.weights.letterboxd, file.weights.movielens, file.weights.tag]
    }

    var filmCount: Int { films.count }

    /// Top `limit` film med højest forudsagt dom.
    /// - Parameters:
    ///   - ratings: brugerens sete film (1–5). Ukendte id'er ignoreres; ved dubletter tæller den første.
    ///   - excludedIDs: film, der aldrig må anbefales (alle sete film).
    func recommend(ratings: [Rating], excluding excludedIDs: Set<Int> = [], limit: Int = 5) -> [Result] {
        let user = UserState(ratings: ratings, model: self)
        guard user.count > 0, limit > 0 else { return [] }

        let excluded = Set(excludedIDs.compactMap { indexByID[$0] }).union(user.ratedIndices)
        let ranked = films.indices
            .filter { !excluded.contains($0) }
            .map { (index: $0, predicted: predict($0, for: user)) }
            .sorted { ($0.predicted, $1.index) > ($1.predicted, $0.index) }

        var seenTitles = Set(user.ratedIndices.map { titleKeys[$0] })
        var results: [Result] = []
        for entry in ranked where seenTitles.insert(titleKeys[entry.index]).inserted {
            results.append(Result(
                movieID: films[entry.index].id,
                predicted: entry.predicted,
                becauseMovieID: bestReason(for: entry.index, user: user).map { films[$0].id }
            ))
            if results.count == limit { break }
        }
        return results
    }

    /// Hvor mange af brugerens domme modellen kan bruge.
    func usableRatingCount(_ ratings: [Rating]) -> Int {
        UserState(ratings: ratings, model: self).count
    }

    // MARK: - Formlen

    /// Forudsagt dom for `films[index]`. Se formlen øverst.
    private func predict(_ index: Int, for user: UserState) -> Double {
        var prediction = user.mean + weights.intercept + weights.filmDeviation * films[index].filmDeviation
        for (source, weight) in zip(sources, sourceWeights) {
            var numerator = 0.0
            var denominator = 0.0
            for neighbor in source[index] {
                guard let residual = user.residuals[neighbor.index] else { continue }
                numerator += neighbor.similarity * residual
                denominator += neighbor.similarity
            }
            if denominator > 0 {
                prediction += weight * numerator / (denominator + shrink)
            }
        }
        return prediction
    }

    /// Den sete film, der bidrager mest positivt til forudsigelsen (summeret over kilderne).
    private func bestReason(for index: Int, user: UserState) -> Int? {
        var contribution: [Int: Double] = [:]
        for (source, weight) in zip(sources, sourceWeights) {
            let rated = source[index].filter { user.residuals[$0.index] != nil }
            let denominator = rated.reduce(0) { $0 + $1.similarity } + shrink
            for neighbor in rated {
                contribution[neighbor.index, default: 0] +=
                    weight * neighbor.similarity * (user.residuals[neighbor.index] ?? 0) / denominator
            }
        }
        return contribution
            .filter { $0.value > 0 }
            .max { ($0.value, $1.key) < ($1.value, $0.key) }?
            .key
    }

    // MARK: - Hjælpere

    nonisolated private struct Neighbor: Sendable {
        let index: Int
        let similarity: Double
    }

    /// Brugerens domme omregnet til modellens indeks.
    nonisolated private struct UserState {
        let mean: Double
        /// `residuals[i]` = dom − mean for sete film, ellers `nil`.
        let residuals: [Double?]
        let ratedIndices: Set<Int>
        var count: Int { ratedIndices.count }

        init(ratings: [Rating], model: RatingRecommender) {
            var scoreByIndex: [Int: Double] = [:]
            for rating in ratings {
                guard let index = model.indexByID[rating.movieID], scoreByIndex[index] == nil else { continue }
                scoreByIndex[index] = rating.score
            }
            let prior = model.personalFromRatings
            let total = scoreByIndex.values.reduce(0, +)
            let mean = (total + prior * model.globalMean) / (Double(scoreByIndex.count) + prior)
            var residuals = [Double?](repeating: nil, count: model.filmCount)
            for (index, score) in scoreByIndex {
                residuals[index] = score - mean
            }
            self.mean = mean
            self.residuals = residuals
            ratedIndices = Set(scoreByIndex.keys)
        }
    }
}
