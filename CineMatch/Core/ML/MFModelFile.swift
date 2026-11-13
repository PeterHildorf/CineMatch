//
//  MFModelFile.swift
//  CineMatch
//

/// Indholdet af `cinematch_mf.json`: Mikkels matrixfaktoriseringsmodel.
/// Formatet er beskrevet i `ml/mikkel_mf/INTEGRATION.md`. Det er et andet format end Antons
/// `cinematch_model.json` og har ingen `formatVersion`: det kendes på `format` + `schemaVersion`.
nonisolated struct MFModelFile: Decodable, Sendable {
    nonisolated struct Movie: Decodable, Sendable {
        /// Film-id i appen.
        let tmdbId: Int
        /// Kun til sporbarhed. Bruges ikke i appen.
        let movieLensId: Int
        /// MovieLens-titel, fx "Matrix, The (1999)". Se `MFTitleParser`.
        let title: String
        let genres: [String]
        /// Filmens egen bias (b_i).
        let bias: Double
        /// Filmens faktorvektor (q_i), præcis `factorCount` tal.
        let factors: [Double]
    }

    let format: String
    let schemaVersion: Int
    let modelType: String
    let modelVersion: String
    let factorCount: Int
    /// Gennemsnitlig rating (mu).
    let globalMean: Double
    /// Straf på den nye brugers faktorvektor.
    let foldInRegularization: Double
    /// Straf på den nye brugers bias.
    let biasRegularization: Double
    /// Rækkefølgen bruges som tie-break.
    let movies: [Movie]
}
