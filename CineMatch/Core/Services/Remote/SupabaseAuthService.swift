//
//  SupabaseAuthService.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import Foundation
import Supabase

/// Den rigtige login-service: e-mail + adgangskode via Supabase Auth.
/// supabase-swift gemmer selv sessionen sikkert i Keychain og fornyer den automatisk.
final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signUp(with credential: AuthCredential) async throws -> SignUpResult {
        switch credential {
        case let .email(address, password):
            do {
                let response = try await client.auth.signUp(email: address, password: password)
                // Er "Confirm email" slået fra i Supabase, får vi en session med det samme.
                if let session = response.session {
                    return .signedIn(makeUserSession(from: session.user))
                }
                return .confirmationRequired
            } catch {
                throw Self.mapError(error)
            }
        }
    }

    func signIn(with credential: AuthCredential) async throws -> UserSession {
        switch credential {
        case let .email(address, password):
            do {
                let session = try await client.auth.signIn(email: address, password: password)
                return makeUserSession(from: session.user)
            } catch {
                throw Self.mapError(error)
            }
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw Self.mapError(error)
        }
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

    // MARK: - Hjælpere

    /// Oversætter Supabase's `User` til vores egen domænemodel,
    /// så resten af appen ikke kender til Supabase.
    private func makeUserSession(from user: User) -> UserSession {
        UserSession(
            // Små bogstaver, så det matcher Postgres' uuid-tekst.
            userID: user.id.uuidString.lowercased(),
            email: user.email
        )
    }

    /// Oversætter Supabase-fejl til vores egne `AuthServiceError`.
    private static func mapError(_ error: Error) -> AuthServiceError {
        if error is URLError { return .network }
        guard let authError = error as? AuthError else { return .unknown }

        switch authError.errorCode {
        case .invalidCredentials:
            return .invalidCredentials
        case .userAlreadyExists, .emailExists:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .emailNotConfirmed:
            return .emailNotConfirmed
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return .tooManyRequests
        default:
            return .unknown
        }
    }
}
