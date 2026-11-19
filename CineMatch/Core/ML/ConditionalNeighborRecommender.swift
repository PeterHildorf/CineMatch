import Foundation

/// Replays the selected Python scorer. Scores are ranking values, never probabilities or star predictions.
nonisolated struct ConditionalNeighborRecommender: Sendable {
    nonisolated struct Rating: Equatable, Sendable {
        let tmdbId: Int
        let stars: Double
    }

    nonisolated struct Result: Equatable, Sendable {
        let tmdbId: Int
        let score: Double
    }

    nonisolated struct Output: Equatable, Sendable {
        let personalized: Bool
        let ratingsUsed: Int
        let positiveRatingsUsed: Int
        let unknownRatedIDs: [Int]
        let results: [Result]
    }

    nonisolated enum LoadError: Error, Equatable {
        case unsupportedFormat
        case unverifiedCatalogue
        case invalidParameters(String)
    }

    nonisolated enum InputError: Error, Equatable {
        case invalidRating(Double)
        case duplicateRating(Int)
        case invalidLimit
    }

    static let supportedFormat = "cinematch.conditional-neighbors"
    static let supportedSchemaVersion = 1
    static let supportedModelType = "positive_conditional_neighbors"

    let modelVersion: String
    let sourceModelSHA256: String
    let legacyMappings: [Int: Int]
    private let file: ConditionalNeighborModelFile
    private let indexByTMDBID: [Int: Int]

    init(file: ConditionalNeighborModelFile) throws {
        guard file.format == Self.supportedFormat,
              file.schemaVersion == Self.supportedSchemaVersion,
              file.modelType == Self.supportedModelType else {
            throw LoadError.unsupportedFormat
        }
        guard file.tmdbIdentityVerified else { throw LoadError.unverifiedCatalogue }
        guard !file.modelVersion.isEmpty,
              file.sourceModelSHA256.count == 64,
              file.sourceModelSHA256.allSatisfy({ $0.isHexDigit }),
              file.scoring.aggregation == "positive",
              file.scoring.ratingCenter == 3,
              file.scoring.fallback == "training_rating_count",
              file.scoring.tieBreak == "original_catalogue_order",
              !file.movies.isEmpty else {
            throw LoadError.invalidParameters("root or scoring contract")
        }

        var index: [Int: Int] = [:]
        var movieLensIDs = Set<Int>()
        for (position, movie) in file.movies.enumerated() {
            guard movie.movieLensId > 0,
                  movieLensIDs.insert(movie.movieLensId).inserted,
                  movie.trainingCount >= 0 else {
                throw LoadError.invalidParameters("movie position \(position)")
            }
            if movie.eligible {
                guard let id = movie.tmdbId, id > 0, index[id] == nil,
                      !movie.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LoadError.invalidParameters("eligible movie position \(position)")
                }
                index[id] = position
            }
        }
        guard !index.isEmpty else { throw LoadError.invalidParameters("empty eligible catalogue") }
        guard file.neighborOffsets.count == file.movies.count + 1,
              file.neighborOffsets.first == 0,
              file.neighborOffsets.last == file.neighborIndices.count,
              file.neighborWeights.count == file.neighborIndices.count,
              file.neighborIndices.allSatisfy({ file.movies.indices.contains($0) }),
              file.neighborWeights.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
            throw LoadError.invalidParameters("neighbour arrays")
        }
        for position in file.movies.indices {
            let start = file.neighborOffsets[position]
            let end = file.neighborOffsets[position + 1]
            guard start >= 0, end >= start, end <= file.neighborIndices.count else {
                throw LoadError.invalidParameters("neighbour offsets at \(position)")
            }
            let targets = file.neighborIndices[start..<end]
            guard Set(targets).count == targets.count else {
                throw LoadError.invalidParameters("duplicate neighbour at \(position)")
            }
        }

        var legacy: [Int: Int] = [:]
        for mapping in file.legacyMappings ?? [] {
            guard mapping.letterboxdId > 0, index[mapping.tmdbId] != nil,
                  legacy[mapping.letterboxdId] == nil else {
                throw LoadError.invalidParameters("legacy mapping \(mapping.letterboxdId)")
            }
            legacy[mapping.letterboxdId] = mapping.tmdbId
        }
        self.file = file
        indexByTMDBID = index
        legacyMappings = legacy
        modelVersion = file.modelVersion
        sourceModelSHA256 = file.sourceModelSHA256
    }

    /// Includes ineligible graph positions, which must not be removed or renumbered.
    var movieCount: Int { file.movies.count }
    var supportedTMDBIDs: Set<Int> { Set(indexByTMDBID.keys) }
    var eligibleMovies: [ConditionalNeighborModelFile.Movie] { file.movies.filter(\.eligible) }

    func movie(tmdbId: Int) -> ConditionalNeighborModelFile.Movie? {
        indexByTMDBID[tmdbId].map { file.movies[$0] }
    }

    func legacyTMDBID(letterboxdId: Int) -> Int? { legacyMappings[letterboxdId] }

    /// Input order is preserved for numeric parity. The service supplies a deterministic order.
    /// Every accepted rating excludes its movie, even when its score contribution is zero.
    func recommend(ratings: [Rating], excluding excludedIDs: Set<Int> = [], limit: Int) throws -> Output {
        guard limit > 0 else { throw InputError.invalidLimit }
        var seen = Set<Int>()
        for rating in ratings {
            guard rating.stars.isFinite, (0.5...5).contains(rating.stars) else {
                throw InputError.invalidRating(rating.stars)
            }
            guard seen.insert(rating.tmdbId).inserted else { throw InputError.duplicateRating(rating.tmdbId) }
        }
        var scores = [Double](repeating: 0, count: file.movies.count)
        var ratingsUsed = 0
        var positiveRatingsUsed = 0
        var unknownRatedIDs: [Int] = []
        for rating in ratings {
            guard let position = indexByTMDBID[rating.tmdbId] else {
                unknownRatedIDs.append(rating.tmdbId)
                continue
            }
            ratingsUsed += 1
            let weight = max(rating.stars - 3, 0)
            guard weight > 0 else { continue }
            positiveRatingsUsed += 1
            for edge in file.neighborOffsets[position]..<file.neighborOffsets[position + 1] {
                scores[file.neighborIndices[edge]] += weight * file.neighborWeights[edge]
            }
        }

        // Match Python: inspect the complete score vector BEFORE eligibility and watched exclusions.
        let personalized = scores.contains { $0 != 0 }
        if !personalized { scores = file.movies.map { Double($0.trainingCount) } }

        let excluded = Set(ratings.map(\.tmdbId)).union(excludedIDs)
        var positions = file.movies.indices.filter { position in
            let movie = file.movies[position]
            return movie.eligible && movie.tmdbId.map { !excluded.contains($0) } == true
        }
        positions.sort { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        let results = positions.prefix(limit).compactMap { position -> Result? in
            guard let id = file.movies[position].tmdbId else { return nil }
            return Result(tmdbId: id, score: scores[position])
        }
        return Output(
            personalized: personalized,
            ratingsUsed: ratingsUsed,
            positiveRatingsUsed: positiveRatingsUsed,
            unknownRatedIDs: unknownRatedIDs,
            results: results
        )
    }
}
