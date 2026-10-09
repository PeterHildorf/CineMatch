//
//  SupabaseAuthService.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import Foundation
import Supabase

/// Den rigtige login-service: Apple-token → Supabase-session.
/// supabase-swift gemmer selv sessionen sikkert i Keychain og fornyer den automatisk.
final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signIn(with credential: AuthCredential) async throws -> UserSession {
        switch credential {
        case let .apple(idToken, rawNonce, fullName, email):
            // Supabase verificerer Apples token og opretter/finder brugeren.
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )

            // Apple sender kun navnet første gang – gem det med det samme på Supabase-brugeren.
            // `try?`: hvis det fejler, er brugeren stadig logget ind, vi mister bare navnet.
            if let fullName {
                _ = try? await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(fullName)])
                )
            }

            return makeUserSession(from: session.user, fallbackName: fullName, fallbackEmail: email)
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func currentSession() async -> UserSession? {
        do {
            // `session` fornyer automatisk et udløbet token. Kaster fejl, hvis der ingen session er.
            let session = try await client.auth.session
            return makeUserSession(from: session.user)
        } catch is URLError {
            // Ingen internet: log IKKE brugeren ud – brug den gemte session, hvis der er en.
            return client.auth.currentSession.map { makeUserSession(from: $0.user) }
        } catch {
            // Sessionen mangler eller er ugyldig: ryd op, så vi starter rent.
            try? await client.auth.signOut()
            return nil
        }
    }

    // MARK: - Hjælper

    /// Oversætter Supabase's `User` til vores egen domænemodel,
    /// så resten af appen ikke kender til Supabase.
    private func makeUserSession(
        from user: User,
        fallbackName: String? = nil,
        fallbackEmail: String? = nil
    ) -> UserSession {
        UserSession(
            // Små bogstaver, så det matcher Postgres' uuid-tekst.
            userID: user.id.uuidString.lowercased(),
            displayName: user.userMetadata["full_name"]?.stringValue ?? fallbackName,
            email: user.email ?? fallbackEmail
        )
    }
}
