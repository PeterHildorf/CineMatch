//
//  RecommendationReasonTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

/// Begrundelsen: "Because you liked X" + det, filmene har til fælles i TMDB.
@MainActor
struct RecommendationReasonTests {
    private let inception = Title(id: 27205, tmdbId: 27205, title: "Inception", year: 2010, genres: ["Action", "Science Fiction"])
    private let interstellar = Title(id: 157336, tmdbId: 157336, title: "Interstellar", year: 2014, genres: ["Drama", "Science Fiction"])

    private func media(_ id: Int, directors: [String] = [], cast: [String] = [], keywords: [String] = []) -> TitleMedia {
        TitleMedia(tmdbId: id, posterURL: nil, directors: directors, cast: cast, keywords: keywords)
    }

    @Test func directorCastAndThemesInOrderMaxTwoGroupsAndTwoValues() {
        let groups = RecommendationReason.sharedGroups(
            title: interstellar,
            media: media(1, directors: ["Christopher Nolan"], cast: ["Matthew McConaughey", "Michael Caine"],
                         keywords: ["dream", "time", "space"]),
            because: inception,
            becauseMedia: media(2, directors: ["Christopher Nolan"], cast: ["Leonardo DiCaprio", "Michael Caine"],
                                keywords: ["space", "time", "dream", "heist"])
        )
        #expect(groups == [
            .init(label: "Director", values: ["Christopher Nolan"]),
            .init(label: "Cast", values: ["Michael Caine"]),
        ])
        #expect(RecommendationReason.text(base: "Because you liked Inception", groups: groups)
            == "Because you liked Inception · Director: Christopher Nolan · Cast: Michael Caine")
    }

    @Test func themesKeepRecommendedFilmsOrderAndAreCappedAtTwo() {
        let groups = RecommendationReason.sharedGroups(
            title: interstellar, media: media(1, keywords: ["dream", "time", "space"]),
            because: inception, becauseMedia: media(2, keywords: ["space", "time", "dream"])
        )
        #expect(groups == [.init(label: "Themes", values: ["dream", "time"])])
    }

    @Test func genresOnlyWhenNothingElseIsShared() {
        let noCredits = RecommendationReason.sharedGroups(
            title: interstellar, media: media(1), because: inception, becauseMedia: media(2)
        )
        #expect(noCredits == [.init(label: "Genres", values: ["Science Fiction"])])
        let noTMDB = RecommendationReason.sharedGroups(title: interstellar, media: nil, because: inception, becauseMedia: nil)
        #expect(noTMDB == noCredits)
    }

    @Test func itemShowsSharedTraitsOnlyWhenItKnowsTheBecauseFilm() {
        let recommendation = Recommendation(rank: 1, movieID: interstellar.id, score: 1, reason: "Because you liked Inception",
                                            becauseMovieID: inception.id)
        var item = RecommendationsViewModel.Item(recommendation: recommendation, title: interstellar)
        #expect(item.reason == "Because you liked Inception")
        item.becauseTitle = inception
        item.media = media(1, directors: ["Christopher Nolan"])
        item.becauseMedia = media(2, directors: ["Christopher Nolan"])
        #expect(item.reason == "Because you liked Inception · Director: Christopher Nolan")
    }

    @Test func overviewAndDirectorFallBackToTMDBWhenTheCatalogueHasNone() {
        let recommendation = Recommendation(rank: 1, movieID: interstellar.id, score: 1, reason: nil)
        var item = RecommendationsViewModel.Item(recommendation: recommendation, title: interstellar)
        #expect(item.overview == nil && item.director == nil)
        item.media = TitleMedia(tmdbId: 1, posterURL: nil, directors: ["Christopher Nolan"], overview: "Explorers travel through a wormhole.")
        #expect(item.overview == "Explorers travel through a wormhole.")
        #expect(item.director == "Christopher Nolan")

        var catalogued = interstellar
        catalogued.overview = "From the catalogue."
        item = RecommendationsViewModel.Item(recommendation: recommendation, title: catalogued, media: item.media)
        #expect(item.overview == "From the catalogue.", "The catalogue wins when it has a description")
    }

    @Test func viewModelLooksUpTheBecauseFilmAndItsCredits() async throws {
        let recommendation = Recommendation(rank: 1, movieID: interstellar.id, score: 1, reason: "Because you liked Inception",
                                            becauseMovieID: inception.id)
        let mediaService = MockTitleMediaService(mediaByTitleID: [
            interstellar.id: media(1, cast: ["Michael Caine"]),
            inception.id: media(2, cast: ["Michael Caine"]),
        ])
        let viewModel = RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: [recommendation]),
            movieDataService: MockMovieDataService(titles: [interstellar, inception]),
            mediaService: mediaService
        )
        await viewModel.load()
        guard case .loaded(let items) = viewModel.state else {
            Issue.record("Expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(items.map(\.id) == [interstellar.id], "The because film is looked up, not recommended")
        #expect(items.first?.reason == "Because you liked Inception · Cast: Michael Caine")
        #expect(Set(mediaService.requestedIDs) == [interstellar.id, inception.id])
    }
}
