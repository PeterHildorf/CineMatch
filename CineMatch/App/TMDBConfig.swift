//
//  TMDBConfig.swift
//  CineMatch
//

import Foundation

/// Læser TMDB-nøglen fra `Secrets.plist` (nøglen `TMDB_READ_ACCESS_TOKEN`).
/// Brug helst "API Read Access Token" fra themoviedb.org → Settings → API. Den korte "API Key" virker også.
struct TMDBConfig {
    let credential: String

    /// Returnerer `nil`, hvis nøglen mangler. Så viser appen pladsholdere i stedet for plakater.
    static func load(from bundle: Bundle = .main) -> TMDBConfig? {
        guard let fileURL = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let credential = values["TMDB_READ_ACCESS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credential.isEmpty,
              !credential.hasPrefix("your-") else {
            return nil
        }
        return TMDBConfig(credential: credential)
    }
}
