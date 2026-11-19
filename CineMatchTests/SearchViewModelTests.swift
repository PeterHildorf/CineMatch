//
//  SearchViewModelTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct SearchViewModelTests {

    private func makeViewModel(_ signals: [TasteSignal]) -> SearchViewModel {
        SearchViewModel(
            movieDataService: MockMovieDataService(),
            signalService: MockTasteSignalService(signals: signals)
        )
    }

    private func load(_ viewModel: SearchViewModel) async {
        await viewModel.loadVerdicts()
        await viewModel.loadSuggestions()
    }

    @Test func ratedFilmsAreHiddenFromBrowse() async {
        let viewModel = makeViewModel([TasteSignal(movieID: 318, verdict: .great)])
        await load(viewModel)

        #expect(!viewModel.browseResults.contains { $0.id == 318 }, "Shawshank er bedømt og skjules")
        #expect(viewModel.browseResults.contains { $0.id == 2571 })
    }

    @Test func notSeenFilmsStayInBrowse() async {
        let viewModel = makeViewModel([TasteSignal(movieID: 318, verdict: .notSeen)])
        await load(viewModel)

        #expect(viewModel.browseResults.contains { $0.id == 318 }, "\"Haven't seen\" er ikke en dom")
    }

    @Test func ratedFilmsCanStillBeSearched() async {
        let viewModel = makeViewModel([TasteSignal(movieID: 318, verdict: .great)])
        await load(viewModel)

        viewModel.query = "Shawshank"
        await viewModel.runSearch()

        #expect(viewModel.results.map(\.id) == [318])
        #expect(viewModel.verdict(for: viewModel.results[0]) == .great, "Søgningen viser den gamle dom")
    }

    @Test func filmRatedNowStaysUntilNextLoad() async {
        let viewModel = makeViewModel([])
        await load(viewModel)
        let matrix = viewModel.browseResults.first { $0.id == 2571 }!

        await viewModel.rate(matrix, .fantastic)
        #expect(viewModel.browseResults.contains { $0.id == 2571 }, "Bliver stående, så man kan fortryde")

        await viewModel.loadVerdicts()
        #expect(!viewModel.browseResults.contains { $0.id == 2571 })
    }

    @Test func genreChipsOnlyCountUnratedFilms() async {
        let viewModel = makeViewModel([TasteSignal(movieID: 1258, verdict: .bad)])
        await load(viewModel)

        #expect(!viewModel.genres.contains("Horror"), "The Shining var den eneste horror-film")
    }
}
