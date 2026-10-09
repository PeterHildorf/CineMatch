//
//  AuthViewModel.swift
//  CineMatch
//

import AuthenticationServices
import Foundation
import Observation

@Observable
@MainActor
final class AuthViewModel {
    enum State: Equatable {
        case loading                 // vi tjekker, om der er en gemt session
        case signedOut
        case signedIn(UserSession)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    var errorMessage: String?

    /// Viser "Log ind som testbruger"-knappen. Kun sand, når vi kører med MockAuthService.
    let allowsTestSignIn: Bool

    private let authService: any AuthService
    /// Den rå nonce for det igangværende Apple-login. Skal sendes videre til Supabase.
    private var currentRawNonce: String?

    init(authService: any AuthService, allowsTestSignIn: Bool = false) {
        self.authService = authService
        self.allowsTestSignIn = allowsTestSignIn
    }

    // MARK: - Opstart

    /// Kaldes når appen starter: er brugeren allerede logget ind?
    func restoreSession() async {
        if let session = await authService.currentSession() {
            state = .signedIn(session)
        } else {
            state = .signedOut
        }
    }

    // MARK: - Sign in with Apple

    /// Kaldes af SignInWithAppleButton lige før Apples login-ark vises.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = Nonce.random()
        currentRawNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(rawNonce)  // Apple får den hashede version
    }

    /// Kaldes når Apples login-ark er færdigt (succes eller fejl).
    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // Brugeren trykkede "Annuller" – det er ikke en fejl, vi skal vise.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = "Login med Apple mislykkedes. Prøv igen."

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = currentRawNonce else {
                errorMessage = "Vi fik ikke et gyldigt svar fra Apple. Prøv igen."
                return
            }

            await signIn(with: .apple(
                idToken: idToken,
                rawNonce: rawNonce,
                fullName: Self.formattedName(credential.fullName),
                email: credential.email
            ))
        }
    }

    // MARK: - Fælles login/logud

    func signIn(with credential: AuthCredential) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }  // køres uanset hvordan funktionen slutter

        do {
            let session = try await authService.signIn(with: credential)
            state = .signedIn(session)
        } catch {
            errorMessage = "Kunne ikke logge ind. Tjek din internetforbindelse og prøv igen."
        }
        currentRawNonce = nil
    }

    /// Kun til udvikling: logger ind uden Apple (virker kun med MockAuthService).
    func signInAsTestUser() async {
        await signIn(with: .apple(idToken: "mock", rawNonce: "mock", fullName: nil, email: nil))
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await authService.signOut()
            state = .signedOut
        } catch {
            errorMessage = "Kunne ikke logge ud. Prøv igen."
        }
    }

    // MARK: - Hjælper

    /// Laver "Peter Hansen" ud af Apples navnekomponenter. `nil` hvis der ikke er noget navn.
    private static func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name.isEmpty ? nil : name
    }
}
