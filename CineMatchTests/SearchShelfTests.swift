//
//  SearchShelfTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

@MainActor
struct SearchShelfTests {

    private func film(_ id: Int, year: Int, genres: [String]) -> Title {
        Title(id: id, tmdbId: id, title: "Film \(id)", year: year, genres: genres)
    }

    @Test func popularComesFirstAndIsNotRepeated() {
        // 60 film fra 90'erne, mest kendte først.
        let titles = (1...60).map { film($0, year: 1995, genres: ["Drama"]) }
        let shelves = SearchShelf.make(from: titles, genres: ["Drama"])

        #expect(shelves.first?.id == "popular")
        #expect(shelves.first?.titles.map(\.id) == Array(1...20))
        let nineties = shelves.first { $0.id == "decade.1990" }
        #expect(nineties?.titles.map(\.id) == Array(21...40), "De populære gentages ikke")
        let drama = shelves.first { $0.id == "genre.Drama" }
        #expect(drama?.titles.map(\.id) == Array(21...40), "Men en film må gerne stå i flere andre rækker")
    }

    @Test func smallShelvesAreLeftOut() {
        let titles = (1...20).map { film($0, year: 2005, genres: ["Comedy"]) }
            + (21...23).map { film($0, year: 1985, genres: ["Horror"]) }
        let shelves = SearchShelf.make(from: titles, genres: ["Comedy", "Horror", "(no genres listed)"])

        #expect(shelves.map(\.id) == ["popular"], "Kun 3 film tilbage i 80s/Horror – for få til en række")
    }
}
