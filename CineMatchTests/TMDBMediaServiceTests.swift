//
//  TMDBMediaServiceTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct TMDBMediaServiceTests {

    /// Falsk netværk: svarer med JSON ud fra stien og husker alle forespørgsler.
    final class StubTransport {
        /// Slutningen af stien → JSON, fx "/movie/603".
        var responses: [String: String]
        private(set) var requests: [URLRequest] = []

        init(_ responses: [String: String] = [:]) {
            self.responses = responses
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let path = request.url?.path() ?? ""
            guard let json = responses.first(where: { path.hasSuffix($0.key) })?.value else {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }

        func query(_ index: Int) -> [String: String] {
            let items = URLComponents(url: requests[index].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }
    }

    private static let matrixDetails = """
    {
      "id": 603,
      "poster_path": "/matrix.jpg",
      "watch/providers": { "results": {
        "DK": {
          "link": "https://www.themoviedb.org/movie/603/watch?locale=DK",
          "flatrate": [
            { "provider_id": 1899, "provider_name": "HBO Max", "logo_path": "/max.jpg", "display_priority": 5 },
            { "provider_id": 8, "provider_name": "Netflix", "logo_path": "/netflix.jpg", "display_priority": 1 }
          ],
          "rent": [ { "provider_id": 2, "provider_name": "Apple TV", "logo_path": "/apple.jpg", "display_priority": 3 } ]
        },
        "US": { "flatrate": [ { "provider_id": 9, "provider_name": "Prime Video", "logo_path": null, "display_priority": 1 } ] }
      } }
    }
    """

    private static let matrixSearch = """
    { "results": [ { "id": 603, "title": "The Matrix", "release_date": "1999-03-30" } ] }
    """

    private func makeService(_ stub: StubTransport, credential: String = "header.payload.signature") -> TMDBMediaService {
        TMDBMediaService(credential: credential, region: "DK") { try await stub.send($0) }
    }

    private let matrix = Title(id: 2571, tmdbId: 603, title: "The Matrix", year: 1999, genres: ["Action"])
    private let matrixWithoutTMDBId = Title(id: 51_000, tmdbId: nil, title: "The Matrix", year: 1999, genres: ["Action"])

    @Test func usesTMDBIdAndReadsPosterAndDanishProviders() async throws {
        let stub = StubTransport(["/movie/603": Self.matrixDetails])

        let media = try #require(await makeService(stub).media(for: matrix))

        #expect(stub.requests.count == 1, "Ingen søgning, når tmdbId er kendt")
        #expect(stub.query(0)["append_to_response"] == "watch/providers")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer header.payload.signature")
        #expect(media.tmdbId == 603)
        #expect(media.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/matrix.jpg")
        #expect(media.streaming.map(\.name) == ["Netflix", "HBO Max"], "Sorteret efter display_priority, kun DK")
        #expect(media.bestProvider?.logoURL?.absoluteString == "https://image.tmdb.org/t/p/w92/netflix.jpg")
        #expect(media.canRentOrBuy)
        #expect(media.watchLink != nil)
    }

    @Test func searchesByTitleAndYearWhenTMDBIdIsMissing() async throws {
        let stub = StubTransport(["/search/movie": Self.matrixSearch, "/movie/603": Self.matrixDetails])

        let media = try #require(await makeService(stub).media(for: matrixWithoutTMDBId))

        #expect(media.tmdbId == 603)
        #expect(stub.requests.count == 2)
        #expect(stub.query(0)["query"] == "The Matrix")
        #expect(stub.query(0)["primary_release_year"] == "1999")
    }

    @Test func searchFallsBackToNeighbouringYear() async throws {
        let stub = StubTransport(["/movie/603": Self.matrixDetails])
        // Første søgning (med år) finder intet, den anden finder filmen med året før.
        var searchCount = 0
        let fallbackService = TMDBMediaService(credential: "a.b.c", region: "DK") { request in
            if request.url!.path().hasSuffix("/search/movie") {
                searchCount += 1
                let json = searchCount == 1
                    ? #"{ "results": [] }"#
                    : #"{ "results": [ { "id": 1, "release_date": "1980-01-01" }, { "id": 603, "release_date": "1998-12-01" } ] }"#
                return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return try await stub.send(request)
        }

        let media = try #require(await fallbackService.media(for: matrixWithoutTMDBId))

        #expect(searchCount == 2)
        #expect(media.tmdbId == 603, "Film fra 1980 er for langt fra 1999")
    }

    @Test func cachesSoSameMovieIsFetchedOnce() async {
        let stub = StubTransport(["/movie/603": Self.matrixDetails])
        let service = makeService(stub)

        _ = await service.media(for: matrix)
        _ = await service.media(for: matrix)

        #expect(stub.requests.count == 1)
    }

    @Test func networkErrorReturnsNilAndIsRetriedLater() async {
        let stub = StubTransport()   // intet svar = netværksfejl
        let service = makeService(stub)

        #expect(await service.media(for: matrix) == nil)

        stub.responses["/movie/603"] = Self.matrixDetails
        #expect(await service.media(for: matrix)?.tmdbId == 603)
    }

    @Test func unknownMovieIsNilAndNotSearchedAgain() async {
        let stub = StubTransport(["/search/movie": #"{ "results": [] }"#])
        let service = makeService(stub)

        #expect(await service.media(for: matrixWithoutTMDBId) == nil)
        #expect(await service.media(for: matrixWithoutTMDBId) == nil)

        #expect(stub.requests.count == 2, "To søgninger første gang, ingen anden gang")
    }

    @Test func movieWithoutDanishStreamingHasNoProvider() async throws {
        let stub = StubTransport(["/movie/603": #"{ "id": 603, "poster_path": null, "watch/providers": { "results": {} } }"#])

        let media = try #require(await makeService(stub).media(for: matrix))

        #expect(media.posterURL == nil)
        #expect(media.bestProvider == nil)
        #expect(!media.canRentOrBuy)
    }

    @Test func shortAPIKeyIsSentInURL() async {
        let stub = StubTransport(["/movie/603": Self.matrixDetails])

        _ = await makeService(stub, credential: "abc123").media(for: matrix)

        #expect(stub.query(0)["api_key"] == "abc123")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func specialCharactersInTitleAreEncoded() async {
        let stub = StubTransport(["/search/movie": #"{ "results": [] }"#])
        let title = Title(id: 1, tmdbId: nil, title: "Fast & Furious", year: 2009, genres: [])

        _ = await makeService(stub).media(for: title)

        #expect(stub.query(0)["query"] == "Fast & Furious")
    }
}

/// ViewModels bruger plakater og streamingtjenester fra `TitleMediaService`.
@MainActor
struct TitleMediaViewModelTests {

    @Test func tastePostersAreLoadedForCurrentAndNextCards() async {
        let titles = MockMovieDataService.sampleTitles
        let poster = URL(string: "https://image.tmdb.org/t/p/w500/x.jpg")!
        let media = MockTitleMediaService(mediaByTitleID: [titles[0].id: TitleMedia(tmdbId: 1, posterURL: poster)])
        let viewModel = TasteViewModel(
            movieDataService: MockMovieDataService(),
            tasteSignalService: MockTasteSignalService(),
            mediaService: media
        )
        await viewModel.load()

        await viewModel.loadPosters()

        #expect(media.requestedIDs == titles.prefix(3).map(\.id))
        #expect(viewModel.posterURLs[titles[0].id] == poster)
        #expect(viewModel.posterURLs[titles[1].id] == nil)
    }

    @Test func recommendationsGetStreamingProvider() async {
        let media = MockTitleMediaService(mediaByTitleID: [2571: MockTitleMediaService.sampleMedia])
        let viewModel = RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: MockRecommendationService.sampleRecommendations),
            movieDataService: MockMovieDataService(),
            mediaService: media
        )

        await viewModel.load()

        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Forventede .loaded, fik \(viewModel.state)")
            return
        }
        #expect(items[0].media?.bestProvider?.name == "Netflix")   // The Matrix
        #expect(items[1].media == nil)
    }
}
