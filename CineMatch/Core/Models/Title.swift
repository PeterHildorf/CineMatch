//
//  Title.swift
//  CineMatch
//

/// En film, brugeren kan bedømme eller få anbefalet.
struct Title: Codable, Hashable, Identifiable, Sendable {
    /// Film-id. Letterboxd-id, når filmen kommer fra modelfilen (MovieLens-id i den gamle liste og i mocks).
    let id: Int
    /// TMDB-id. Bruges til plakater og streamingtjenester (`TMDBMediaService`).
    /// `nil` for film fra modelfilen indtil videre. Så søges de frem på titel og år.
    let tmdbId: Int?
    let title: String
    let year: Int
    /// Genrer på engelsk, fx "Comedy" og "Science Fiction".
    let genres: [String]
    /// Fra modelfilen. `nil` for film fra den gamle MovieLens-liste.
    var director: String? = nil
    /// Skuespillere som kommasepareret streng, fx "Adam Driver, Greta Gerwig". `nil` uden data.
    /// Bruges til at søge på skuespiller og vise dem på rækken.
    var cast: String? = nil
    var overview: String? = nil
    var runtimeMinutes: Int? = nil
}
