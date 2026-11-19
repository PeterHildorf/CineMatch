//
//  RatingModelFile.swift
//  CineMatch
//

import Foundation

/// Indholdet af `cinematch_rating_model.json`: Antons nye model, der forudsiger brugerens dom (1–5) for hver film.
///
/// Filen har KUN det, modellen regner med. Titler, år, genrer osv. ligger stadig i `cinematch_model.json`
/// (`ModelFile`), og begge filer har de samme film i samme rækkefølge.
nonisolated struct RatingModelFile: Decodable, Sendable {
    nonisolated struct Film: Decodable, Hashable, Sendable {
        /// Letterboxd-id – samme id som i `cinematch_model.json`.
        let id: Int
        let title: String
        /// Hvor meget filmen typisk ligger over/under gennemsnittet.
        let filmDeviation: Double
    }

    /// Vægte i den lineære kombination (se `RatingRecommender`).
    nonisolated struct Weights: Decodable, Hashable, Sendable {
        let letterboxd: Double
        let movielens: Double
        let tag: Double
        let filmDeviation: Double
        let intercept: Double
    }

    let ratingFormatVersion: Int
    /// Mangler i den første fil. Så bruger appen "rating-v<ratingFormatVersion>" i målingerne.
    let modelVersion: String?
    /// Lægges til nævneren i nabo-gennemsnittet, så få/svage naboer ikke giver store udsving.
    let shrink: Double
    /// Gennemsnitsdommen i træningsdata.
    let globalMean: Double
    /// Så mange domme skal der til, før brugerens eget gennemsnit vejer lige så meget som `globalMean`.
    let personalFromRatings: Double
    let weights: Weights
    let films: [Film]
    /// `xNeighbors[i]` er naboerne til `films[i]`: `[index i films, similarity]`, bedste først.
    let letterboxdNeighbors: [[[Double]]]
    let movielensNeighbors: [[[Double]]]
    let tagNeighbors: [[[Double]]]
}
