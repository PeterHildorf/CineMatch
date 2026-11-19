//
//  TitleMedia.swift
//  CineMatch
//

import Foundation

/// Plakat og streamingtjenester for én film. Kommer fra TMDB via `TitleMediaService`.
struct TitleMedia: Hashable, Sendable {
    let tmdbId: Int
    let posterURL: URL?
    /// Tjenester med abonnement (Netflix, Viaplay …) i brugerens land, mest populære først.
    var streaming: [StreamingProvider] = []
    /// True, hvis filmen kan lejes eller købes (fx Apple TV, Blockbuster).
    var canRentOrBuy = false
    /// TMDB's side med links til tjenesterne.
    var watchLink: URL? = nil
    /// Instruktør(er), fra TMDB's credits.
    var directors: [String] = []
    /// De første navne på rollelisten (hovedrollerne først).
    var cast: [String] = []
    /// TMDB-keywords, fx "dream", "heist". Bruges som "Themes" i begrundelsen.
    var keywords: [String] = []
    /// Kort handlingsbeskrivelse fra TMDB (engelsk). `nil`, hvis TMDB ikke har en.
    var overview: String? = nil

    /// Den tjeneste, kortet viser. I dag den mest populære i landet.
    /// TODO: Vælg ud fra de tjenester, brugeren selv har.
    var bestProvider: StreamingProvider? { streaming.first }
}

/// En streamingtjeneste, fx Netflix. Data fra JustWatch via TMDB.
struct StreamingProvider: Hashable, Identifiable, Sendable {
    /// TMDB's provider-id (Netflix = 8).
    let id: Int
    let name: String
    let logoURL: URL?
}
