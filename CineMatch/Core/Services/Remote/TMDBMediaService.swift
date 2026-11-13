//
//  TMDBMediaService.swift
//  CineMatch
//

import Foundation

/// Plakater og streamingtjenester fra TMDB (themoviedb.org). Streamingdata kommer fra JustWatch.
///
/// - Filmen findes via `tmdbId`. Film fra modelfilen har ikke et endnu, så de søges frem på titel og år.
/// - Ét kald pr. film: detaljer + "watch/providers" (`append_to_response`).
/// - Svar gemmes i hukommelsen, så samme film kun hentes én gang, mens appen kører.
final class TMDBMediaService: TitleMediaService {
    /// Sender én HTTP-forespørgsel. Byttes ud med et falsk netværk i tests.
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private let credential: String
    /// Landekode til streamingtjenester, fx "DK".
    private let region: String
    private let transport: Transport

    /// Svar pr. film-id. `nil` som værdi = TMDB kender ikke filmen (så spørger vi ikke igen).
    private var cache: [Int: TitleMedia?] = [:]
    /// Opslag, der er i gang, så to skærme ikke henter den samme film samtidig.
    private var inFlight: [Int: Task<TitleMedia?, Error>] = [:]

    init(
        credential: String,
        region: String = "DK",
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.credential = credential
        self.region = region
        self.transport = transport
    }

    func media(for title: Title) async -> TitleMedia? {
        if let cached = cache[title.id] { return cached }

        let task = inFlight[title.id] ?? Task { try await self.fetch(title) }
        inFlight[title.id] = task
        defer { inFlight[title.id] = nil }

        do {
            let media = try await task.value
            cache.updateValue(media, forKey: title.id)   // gemmer også `nil` (ukendt film)
            return media
        } catch {
            // Netværksfejl gemmes ikke, så næste forsøg prøver igen.
            return nil
        }
    }

    // MARK: - Opslag

    private func fetch(_ title: Title) async throws -> TitleMedia? {
        guard let tmdbId = try await resolveID(for: title) else { return nil }
        let details: MovieDetails = try await get(
            "movie/\(tmdbId)",
            query: ["append_to_response": "watch/providers", "language": "en-US"]
        )
        return media(from: details)
    }

    /// TMDB-id'et: direkte fra filmen, ellers ved at søge på titel og år.
    private func resolveID(for title: Title) async throws -> Int? {
        if let tmdbId = title.tmdbId { return tmdbId }

        // Først med året, så "Dune" (2021) ikke bliver til "Dune" (1984).
        let exact: SearchResponse = try await get("search/movie", query: [
            "query": title.title, "primary_release_year": String(title.year), "include_adult": "false",
        ])
        if let hit = exact.results.first { return hit.id }

        // Året kan være ét ved siden af (festivalpremiere vs. biografpremiere).
        let loose: SearchResponse = try await get("search/movie", query: [
            "query": title.title, "include_adult": "false",
        ])
        return loose.results.first { result in
            guard let year = result.year else { return false }
            return abs(year - title.year) <= 1
        }?.id
    }

    private func media(from details: MovieDetails) -> TitleMedia {
        let country = details.watchProviders?.results[region]
        let streaming = (country?.flatrate ?? [])
            .sorted { ($0.displayPriority ?? .max) < ($1.displayPriority ?? .max) }
            .map { StreamingProvider(id: $0.providerId, name: $0.providerName, logoURL: Self.imageURL($0.logoPath, size: "w92")) }
        return TitleMedia(
            tmdbId: details.id,
            posterURL: Self.imageURL(details.posterPath, size: "w500"),
            streaming: streaming,
            canRentOrBuy: !(country?.rent ?? []).isEmpty || !(country?.buy ?? []).isEmpty,
            watchLink: country?.link.flatMap(URL.init(string:))
        )
    }

    static func imageURL(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - HTTP

    /// Read Access Token (lang, med punktummer) sendes som header. Den korte v3-nøgle sendes i URL'en.
    private var usesBearerToken: Bool { credential.contains(".") }

    /// Tegn, der må stå ukodet i en query-værdi. `&`, `=` og `+` skal kodes, ellers går "Fast & Furious" i stykker.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?/")
        return allowed
    }()

    private func get<Response: Decodable>(_ path: String, query: [String: String]) async throws -> Response {
        var parameters = query
        if !usesBearerToken { parameters["api_key"] = credential }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.themoviedb.org"
        components.path = "/3/" + path
        components.percentEncodedQueryItems = parameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed))
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesBearerToken {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - TMDB's JSON

/// `GET /search/movie`
private nonisolated struct SearchResponse: Decodable {
    nonisolated struct Result: Decodable {
        let id: Int
        let releaseDate: String?

        var year: Int? { releaseDate.flatMap { Int($0.prefix(4)) } }

        nonisolated enum CodingKeys: String, CodingKey {
            case id
            case releaseDate = "release_date"
        }
    }

    let results: [Result]
}

/// `GET /movie/{id}?append_to_response=watch/providers`
private nonisolated struct MovieDetails: Decodable {
    let id: Int
    let posterPath: String?
    let watchProviders: WatchProviders?

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case posterPath = "poster_path"
        case watchProviders = "watch/providers"
    }

    nonisolated struct WatchProviders: Decodable {
        /// Pr. landekode, fx "DK".
        let results: [String: Country]
    }

    nonisolated struct Country: Decodable {
        let link: String?
        /// Abonnement (Netflix, Viaplay …).
        let flatrate: [Provider]?
        let rent: [Provider]?
        let buy: [Provider]?
    }

    nonisolated struct Provider: Decodable {
        let providerId: Int
        let providerName: String
        let logoPath: String?
        let displayPriority: Int?

        nonisolated enum CodingKeys: String, CodingKey {
            case providerId = "provider_id"
            case providerName = "provider_name"
            case logoPath = "logo_path"
            case displayPriority = "display_priority"
        }
    }
}
