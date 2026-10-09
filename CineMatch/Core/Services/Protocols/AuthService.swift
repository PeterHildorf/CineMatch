//
//  AuthService.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

/// De måder brugeren kan logge ind på. Nye metoder tilføjes som en ny `case`,
/// uden at resten af appen skal ændres.
enum AuthCredential: Sendable {
    /// - idToken: Apples identity token (en JWT), som Supabase verificerer.
    /// - rawNonce: Den ukrypterede nonce. Apple fik den hashede version, Supabase skal have denne.
    /// - fullName/email: Apple sender dem KUN første gang brugeren logger ind.
    case apple(idToken: String, rawNonce: String, fullName: String?, email: String?)
    // senere: case email(address: String, password: String)
}

protocol AuthService: Sendable {
    func signIn(with credential: AuthCredential) async throws -> UserSession
    func signOut() async throws
    /// Den gemte session, hvis den stadig er gyldig. `nil` betyder "ikke logget ind".
    func currentSession() async -> UserSession?
}
