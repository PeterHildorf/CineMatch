//
//  TestUserConfig.swift
//  CineMatch
//

import Foundation

/// Testbrugeren til `-freshUser`: læses fra `Secrets.plist` (`TEST_USER_EMAIL`, `TEST_USER_PASSWORD`).
/// Brugeren skal findes i Supabase (Authentication → Users → Add user, "Auto Confirm User").
struct TestUserConfig {
    static let defaultEmail = "test@bruger.com"

    let email: String
    let password: String

    /// `nil`, hvis adgangskoden mangler. Så kan appen ikke starte som testbruger.
    static func load(from bundle: Bundle = .main) -> TestUserConfig? {
        guard let fileURL = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let password = values["TEST_USER_PASSWORD"], !password.isEmpty, !password.hasPrefix("your-") else {
            return nil
        }
        let email = values["TEST_USER_EMAIL"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultEmail
        return TestUserConfig(email: email, password: password)
    }
}
