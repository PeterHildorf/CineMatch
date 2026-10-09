//
//  MockAuthService.swift
//  CineMatch
//

import Foundation

/// Falsk login-service til Simulator, previews og tests.
/// Gemmer sessionen i hukommelsen og taler ikke med Apple eller Supabase.
final class MockAuthService: AuthService {
    static let sampleSession = UserSession(
        userID: "mock-user-id",
        displayName: "Test Bruger",
        email: "test@cinematch.dev"
    )

    /// Den "gemte" session. Sæt den i init for at simulere en bruger, der allerede er logget ind.
    var storedSession: UserSession?
    /// Sæt en fejl her i tests for at simulere at login/logud fejler.
    var errorToThrow: Error?

    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(storedSession: UserSession? = nil, errorToThrow: Error? = nil) {
        self.storedSession = storedSession
        self.errorToThrow = errorToThrow
    }

    func signIn(with credential: AuthCredential) async throws -> UserSession {
        signInCallCount += 1
        if let errorToThrow { throw errorToThrow }

        let session: UserSession
        switch credential {
        case let .apple(_, _, fullName, email):
            session = UserSession(
                userID: Self.sampleSession.userID,
                displayName: fullName ?? Self.sampleSession.displayName,
                email: email ?? Self.sampleSession.email
            )
        }
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
}
