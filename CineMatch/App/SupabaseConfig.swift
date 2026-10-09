//
//  SupabaseConfig.swift
//  CineMatch
//

import Foundation

/// Læser Supabase URL + anon key fra `Secrets.plist`.
/// Secrets.plist er i .gitignore – kopiér `Secrets.example.plist` og udfyld den.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    /// Returnerer `nil`, hvis filen mangler eller stadig indeholder eksempel-værdierne.
    /// Så bruger appen MockAuthService i stedet.
    static func load(from bundle: Bundle = .main) -> SupabaseConfig? {
        guard let fileURL = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let urlString = values["SUPABASE_URL"],
              let url = URL(string: urlString),
              let anonKey = values["SUPABASE_ANON_KEY"],
              !anonKey.isEmpty,
              !urlString.contains("YOUR-PROJECT") else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}
