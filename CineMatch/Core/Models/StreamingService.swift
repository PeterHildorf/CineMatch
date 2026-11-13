//
//  StreamingService.swift
//  CineMatch
//

import Foundation

/// En streamingtjeneste, brugeren kan vælge i "Which services do you have?".
/// Kun abonnementstjenester i Danmark. Leje og køb (fx Apple TV, Blockbuster) tæller ikke.
enum StreamingService: String, CaseIterable, Codable, Identifiable, Sendable {
    case netflix
    case primeVideo
    case disneyPlus
    case hboMax
    case appleTVPlus
    case viaplay
    case tv2Play

    var id: String { rawValue }

    /// Navnet i appen (engelsk UI, men tjenesternes egne navne).
    var name: String {
        switch self {
        case .netflix: "Netflix"
        case .primeVideo: "Prime Video"
        case .disneyPlus: "Disney+"
        case .hboMax: "HBO Max"
        case .appleTVPlus: "Apple TV+"
        case .viaplay: "Viaplay"
        case .tv2Play: "TV 2 Play"
        }
    }

    /// Kort mærke til listen, fx "N" og "D+".
    var badge: String {
        switch self {
        case .netflix: "N"
        case .primeVideo: "P"
        case .disneyPlus: "D+"
        case .hboMax: "H"
        case .appleTVPlus: "A"
        case .viaplay: "V"
        case .tv2Play: "2"
        }
    }

    /// TMDB's provider-id'er. Navnet bruges som reserve, hvis TMDB skifter id (det sker ved omdøbning).
    private var tmdbProviderIDs: Set<Int> {
        switch self {
        case .netflix: [8, 1796]            // 1796 = "Netflix Standard with Ads"
        case .primeVideo: [9, 119]
        case .disneyPlus: [337]
        case .hboMax: [384, 1899]           // HBO Max → Max → HBO Max
        case .appleTVPlus: [350]
        case .viaplay: [76]
        case .tv2Play: [383]
        }
    }

    /// Normaliserede navne, som TMDB's providernavn kan starte med.
    private var namePrefixes: [String] {
        switch self {
        case .netflix: ["netflix"]
        case .primeVideo: ["amazonprimevideo", "primevideo"]
        case .disneyPlus: ["disneyplus"]
        case .hboMax: ["hbomax"]
        case .appleTVPlus: ["appletvplus"]
        case .viaplay: ["viaplay"]
        case .tv2Play: ["tv2play"]
        }
    }

    /// True, hvis TMDB-provideren er denne tjeneste.
    func matches(_ provider: StreamingProvider) -> Bool {
        if tmdbProviderIDs.contains(provider.id) { return true }
        let name = Self.normalize(provider.name)
        return namePrefixes.contains { name.hasPrefix($0) }
    }

    /// "Disney Plus" og "Disney+" → "disneyplus". "TV 2 Play" → "tv2play".
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "+", with: "plus")
            .filter { $0.isLetter || $0.isNumber }
    }
}

extension TitleMedia {
    /// Den første tjeneste (mest populære først), som brugeren har. `nil`, hvis ingen.
    func provider(in services: Set<StreamingService>) -> StreamingProvider? {
        streaming.first { provider in services.contains { $0.matches(provider) } }
    }
}
