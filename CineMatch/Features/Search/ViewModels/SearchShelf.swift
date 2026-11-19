//
//  SearchShelf.swift
//  CineMatch
//

import Foundation

/// Én vandret række plakater i den nye Search (fx "Popular", "90s", "Comedy").
///
/// Rækker med plakater i stedet for én lang liste: folk husker sjældent, hvilke film de har set,
/// men genkender dem på plakaten. Mange genkendelige plakater på kort tid = flere bedømmelser.
struct SearchShelf: Identifiable {
    let id: String
    let title: String
    let titles: [Title]

    /// Så mange film pr. række.
    static let size = 20
    /// Færre film end det, og rækken vises ikke.
    static let minimumSize = 4
    /// Så mange genre-rækker højst.
    static let maxGenres = 8

    /// Bygger rækkerne. `titles` skal være sorteret med de mest kendte først.
    ///
    /// Filmene i "Popular" gentages ikke i de andre rækker, så de ikke fylder det hele.
    /// Ellers må en film godt stå i flere rækker (fx både "90s" og "Drama").
    static func make(from titles: [Title], genres: [String]) -> [SearchShelf] {
        var shelves: [SearchShelf] = []
        var popularIDs: Set<Int> = []

        func add(_ id: String, _ title: String, where matches: (Title) -> Bool) {
            // Almindelig løkke, der stopper ved `size` film (`lazy.filter` kræver en escaping closure).
            var picked: [Title] = []
            for title in titles where !popularIDs.contains(title.id) && matches(title) {
                picked.append(title)
                if picked.count == size { break }
            }
            guard picked.count >= minimumSize else { return }
            shelves.append(SearchShelf(id: id, title: title, titles: picked))
        }

        add("popular", "Popular") { _ in true }
        popularIDs = Set(shelves.first?.titles.map(\.id) ?? [])

        for (start, name) in [(2010, "2010s"), (2000, "2000s"), (1990, "90s"), (1980, "80s")] {
            add("decade.\(start)", name) { (start..<start + 10).contains($0.year) }
        }
        add("decade.older", "Classics before 1980") { $0.year > 0 && $0.year < 1980 }

        for genre in genres.filter({ !$0.hasPrefix("(") }).prefix(maxGenres) {
            add("genre.\(genre)", genre) { $0.genres.contains(genre) }
        }
        return shelves
    }
}

extension SearchViewModel {
    /// Rækkerne i den nye Search, bygget af de film, brugeren ikke har bedømt endnu.
    var shelves: [SearchShelf] {
        SearchShelf.make(from: browseResults, genres: genres)
    }
}
