//
//  MatrixFactorizationRecommender.swift
//  CineMatch
//

import Foundation

/// Mikkels matrixfaktoriseringsmodel, kørt lokalt på telefonen.
///
/// Modellen forudsiger, hvad brugeren ville give en film i stjerner. Brugerens egen profil
/// regnes ud fra hans stjerner ("fold-in", en lille ridge-regression), så alle film i kataloget kan scores:
///
///     base_i  = mu + b_i
///     løs (A) · [userBias, userFactors] = z     A = diag(biasReg, foldInReg, …) + Σ x xᵀ,  z = Σ x · (r − base)
///     score_i = base_i + userBias + q_i · userFactors
///
/// Regner præcis som Python (se `mf_reference_cases.json` og testene).
/// Scoren er en rå rangeringsværdi – ikke en match-procent og ikke en sikker stjerne-forudsigelse.
nonisolated struct MatrixFactorizationRecommender: Sendable {
    nonisolated struct Rating: Equatable, Sendable {
        let tmdbId: Int
        /// ½–5 stjerner i halve trin.
        let stars: Double
    }

    nonisolated struct Result: Equatable, Sendable {
        let tmdbId: Int
        let score: Double
    }

    nonisolated struct Output: Equatable, Sendable {
        /// `false`, når der ingen ratings er (så er listen bare filmenes gennemsnit – ikke personlig).
        let personalized: Bool
        let ratingsUsed: Int
        /// Ratede film, som ikke findes i modellen. De ignoreres.
        let unknownRatedIDs: [Int]
        let results: [Result]
    }

    nonisolated enum LoadError: Error, Equatable {
        case unsupportedFormat
        case invalidParameters(String)
    }

    nonisolated enum InputError: Error, Equatable {
        case invalidRating(Double)
        case duplicateRating(Int)
        case invalidLimit
    }

    static let supportedFormat = "cinematch.matrix-factorization"
    static let supportedSchemaVersion = 1
    static let supportedModelType = "explicit_rating_matrix_factorization"

    let modelVersion: String
    private let file: MFModelFile
    private let indexByTMDBId: [Int: Int]

    init(file: MFModelFile) throws {
        guard file.format == Self.supportedFormat,
              file.schemaVersion == Self.supportedSchemaVersion,
              file.modelType == Self.supportedModelType else {
            throw LoadError.unsupportedFormat
        }
        guard file.factorCount > 0,
              file.globalMean.isFinite,
              file.foldInRegularization.isFinite, file.foldInRegularization > 0,
              file.biasRegularization.isFinite, file.biasRegularization > 0 else {
            throw LoadError.invalidParameters("root")
        }
        var index: [Int: Int] = [:]
        for (position, movie) in file.movies.enumerated() {
            guard movie.tmdbId > 0, index[movie.tmdbId] == nil else {
                throw LoadError.invalidParameters("tmdbId \(movie.tmdbId)")
            }
            guard movie.factors.count == file.factorCount,
                  movie.bias.isFinite,
                  movie.factors.allSatisfy(\.isFinite) else {
                throw LoadError.invalidParameters("movie \(movie.tmdbId)")
            }
            index[movie.tmdbId] = position
        }
        self.file = file
        indexByTMDBId = index
        modelVersion = file.modelVersion
    }

    var movieCount: Int { file.movies.count }

    func movie(tmdbId: Int) -> MFModelFile.Movie? {
        indexByTMDBId[tmdbId].map { file.movies[$0] }
    }

    // MARK: - Anbefalinger

    /// De `limit` bedste film ud fra brugerens stjerner.
    /// Ratede film og `excluding` anbefales aldrig. Ukendte id'er i `excluding` ignoreres.
    func recommend(ratings: [Rating], excluding excludedIDs: Set<Int> = [], limit: Int) throws -> Output {
        guard limit > 0 else { throw InputError.invalidLimit }
        var seen = Set<Int>()
        for rating in ratings {
            guard rating.stars.isFinite, (0.5...5).contains(rating.stars),
                  (rating.stars * 2).rounded() == rating.stars * 2 else {
                throw InputError.invalidRating(rating.stars)
            }
            guard seen.insert(rating.tmdbId).inserted else { throw InputError.duplicateRating(rating.tmdbId) }
        }

        let known = ratings.filter { indexByTMDBId[$0.tmdbId] != nil }
        let unknown = ratings.filter { indexByTMDBId[$0.tmdbId] == nil }.map(\.tmdbId)
        let user = known.isEmpty ? [Double](repeating: 0, count: file.factorCount + 1) : foldIn(known)
        let userBias = user[0]
        let userFactors = user.dropFirst()

        let excluded = Set(ratings.map(\.tmdbId)).union(excludedIDs)
        var scored: [(score: Double, position: Int)] = []
        scored.reserveCapacity(file.movies.count)
        for (position, movie) in file.movies.enumerated() where !excluded.contains(movie.tmdbId) {
            var dot = 0.0
            for (q, u) in zip(movie.factors, userFactors) { dot += q * u }
            scored.append((file.globalMean + movie.bias + userBias + dot, position))
        }
        // Højeste score først. Ved præcis samme score: rækkefølgen i filen.
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.position < $1.position }

        return Output(
            personalized: !known.isEmpty,
            ratingsUsed: known.count,
            unknownRatedIDs: unknown,
            results: scored.prefix(limit).map { Result(tmdbId: file.movies[$0.position].tmdbId, score: $0.score) }
        )
    }

    /// Regner brugerens bias og faktorvektor ud fra hans ratings. Returnerer `[userBias] + userFactors`.
    private func foldIn(_ ratings: [Rating]) -> [Double] {
        let size = file.factorCount + 1
        var a = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        var z = [Double](repeating: 0, count: size)
        a[0][0] = file.biasRegularization
        for i in 1..<size { a[i][i] = file.foldInRegularization }

        for rating in ratings {
            guard let index = indexByTMDBId[rating.tmdbId] else { continue }
            let movie = file.movies[index]
            let x = [1.0] + movie.factors
            let y = rating.stars - (file.globalMean + movie.bias)
            for row in 0..<size {
                z[row] += x[row] * y
                for column in 0..<size { a[row][column] += x[row] * x[column] }
            }
        }
        return Self.solve(a, z)
    }

    /// Løser A · x = b med Gauss-elimination og delvis pivotering. A er symmetrisk positiv definit (17×17).
    static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        var a = matrix
        var b = vector
        let n = b.count
        for column in 0..<n {
            let pivot = (column..<n).max { abs(a[$0][column]) < abs(a[$1][column]) } ?? column
            if pivot != column {
                a.swapAt(pivot, column)
                b.swapAt(pivot, column)
            }
            for row in (column + 1)..<n {
                let factor = a[row][column] / a[column][column]
                guard factor != 0 else { continue }
                for k in column..<n { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }
}

/// MovieLens-titler → pæne titler: "Matrix, The (1999)" → "The Matrix", 1999.
nonisolated enum MFTitleParser {
    private static let articles = ["The", "A", "An", "Les", "La", "Le", "L'", "Il", "Das", "Der", "Die", "El", "Los", "Las", "Det", "Den"]

    static func parse(_ raw: String) -> (title: String, year: Int?) {
        var title = raw.trimmingCharacters(in: .whitespaces)
        var year: Int?

        // Året til sidst: "(1999)".
        if title.hasSuffix(")"), let open = title.lastIndex(of: "(") {
            let inside = title[title.index(after: open)..<title.index(before: title.endIndex)]
            if inside.count == 4, let value = Int(inside) {
                year = value
                title = title[..<open].trimmingCharacters(in: .whitespaces)
            }
        }
        // Alternative titler: "Seven (a.k.a. Se7en)" → "Seven".
        while title.hasSuffix(")"), let open = title.lastIndex(of: "("), open > title.startIndex {
            title = title[..<open].trimmingCharacters(in: .whitespaces)
        }
        // Artikel bagerst: "Matrix, The" → "The Matrix".
        for article in articles where title.hasSuffix(", \(article)") {
            let base = title.dropLast(article.count + 2)
            title = article.hasSuffix("'") ? "\(article)\(base)" : "\(article) \(base)"
            break
        }
        return (title, year)
    }
}
