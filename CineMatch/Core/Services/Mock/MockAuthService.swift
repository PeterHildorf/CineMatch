//
//  MockAuthService.swift
//  CineMatch
//

import Foundation

/// Falsk login-service til previews og tests.
/// Gemmer sessionen i hukommelsen og taler ikke med Supabase.
final class MockAuthService: AuthService {
    static let sampleSession = UserSession(
        userID: "mock-user-id",
        email: "test@cinematch.dev"
    )

    /// Den "gemte" session. Sæt den i init for at simulere en bruger, der allerede er logget ind.
    var storedSession: UserSession?
    /// Sæt en fejl her i tests for at simulere at login/logud fejler.
    var errorToThrow: Error?
    /// Sæt til `true` for at simulere at Supabase kræver e-mail-bekræftelse.
    var requiresEmailConfirmation = false

    private(set) var signUpCallCount = 0
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(storedSession: UserSession? = nil, errorToThrow: Error? = nil) {
        self.storedSession = storedSession
        self.errorToThrow = errorToThrow
    }

    func signUp(with credential: AuthCredential) async throws -> SignUpResult {
        signUpCallCount += 1
        if let errorToThrow { throw errorToThrow }
        if requiresEmailConfirmation { return .confirmationRequired }

        let session = makeSession(from: credential)
        storedSession = session
        return .signedIn(session)
    }

    func signIn(with credential: AuthCredential) async throws -> UserSession {
        signInCallCount += 1
        if let errorToThrow { throw errorToThrow }

        let session = makeSession(from: credential)
        storedSession = session
        return session
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let errorToThrow { throw errorToThrow }
        storedSession = nil
    }

    func currentSession() async -> UserSession? {
        storedSession
    }

    private func makeSession(from credential: AuthCredential) -> UserSession {
        switch credential {
        case let .email(address, _):
            return UserSession(userID: Self.sampleSession.userID, email: address)
        }
    }
}
