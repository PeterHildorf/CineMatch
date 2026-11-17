//
//  LocalJSONMovieDataService.swift
//  CineMatch
//

import Foundation

/// Læser filmlisten fra `movielens_titles.json`, som ligger i app-bundlen.
/// Filen er lavet ud fra MovieLens `ml-latest-small` (movies.csv + links.csv).
struct LocalJSONMovieDataService: MovieDataService {
    private let fileName: String
    private let bundle: Bundle

    init(fileName: String = "movielens_titles", bundle: Bundle = .main) {
        self.fileName = fileName
        self.bundle = bundle
    }

    func allTitles() async throws -> [Title] {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            AppLog.shared.error("\(fileName).json not found in app bundle")
            throw MovieDataServiceError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Title].self, from: data)
        } catch {
            AppLog.shared.error("Couldn't load \(fileName).json", error)
            throw MovieDataServiceError.invalidData
        }
    }
}
