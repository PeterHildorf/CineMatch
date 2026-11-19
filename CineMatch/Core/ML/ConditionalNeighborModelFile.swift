/// Exported conditional-neighbour graph. Movie positions always match the frozen training artifact.
nonisolated struct ConditionalNeighborModelFile: Decodable, Sendable {
    nonisolated struct Movie: Decodable, Sendable {
        let movieLensId: Int
        let tmdbId: Int?
        let eligible: Bool
        let title: String
        let year: Int
        let genres: [String]
        let trainingCount: Int
    }

    nonisolated struct Scoring: Decodable, Sendable {
        let aggregation: String
        let ratingCenter: Double
        let fallback: String
        let tieBreak: String
    }

    nonisolated struct LegacyMapping: Decodable, Sendable {
        let letterboxdId: Int
        let tmdbId: Int
    }

    let format: String
    let schemaVersion: Int
    let modelType: String
    let modelVersion: String
    let sourceModelSHA256: String
    let tmdbIdentityVerified: Bool
    let scoring: Scoring
    let movies: [Movie]
    let neighborOffsets: [Int]
    let neighborIndices: [Int]
    let neighborWeights: [Double]
    /// Only verified translations into the eligible catalogue may appear here.
    let legacyMappings: [LegacyMapping]?
}
