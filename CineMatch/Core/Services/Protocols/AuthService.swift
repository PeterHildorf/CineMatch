//
//  AuthService.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

/// De måder brugeren kan logge ind på. Nye metoder tilføjes som en ny `case`,
/// uden at resten af appen skal ændres.
enum AuthCredential: Sendable {
    case email(address: String, password: String)
    // senere fx: case anonymous
}

/// Resultatet af at oprette en konto.
enum SignUpResult: Equatable, Sendable {
    /// Kontoen er oprettet, og brugeren er logget ind med det samme.
    case signedIn(UserSession)
    /// Kontoen er oprettet, men brugeren skal først bekræfte sin e-mail.
    case confirmationRequired
}

/// Fejl som resten af appen forstår – uafhængigt af om vi bruger Supabase eller noget andet.
/// (Ligesom egne exception-klasser i Java.)
enum AuthServiceError: Error, Equatable {
    case invalidCredentials     // forkert e-mail eller adgangskode
    case emailAlreadyInUse
    case weakPassword
    case emailNotConfirmed
    case tooManyRequests
    case network
    case unknown
}

protocol AuthService: Sendable {
    func signUp(with credential: AuthCredential) async throws -> SignUpResult
    func signIn(with credential: AuthCredential) async throws -> UserSession
    func signOut() async throws
    /// Den gemte session, hvis den stadig er gyldig. `nil` betyder "ikke logget ind".
    func currentSession() async -> UserSession?
}
