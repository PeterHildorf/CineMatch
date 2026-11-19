//
//  AuthViewModel.swift
//  CineMatch
//

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

    /// Om formularen skal logge ind eller oprette en ny konto.
    enum Mode {
        case signIn
        case signUp
    }

    /// Supabase kræver som standard mindst 6 tegn.
    static let minimumPasswordLength = 6

    private(set) var state: State = .loading
    private(set) var isWorking = false

    // Formularens felter – bindes direkte til TextField/SecureField i viewet.
    var mode: Mode = .signIn
    var email = ""
    var password = ""

    /// Rød besked når noget går galt.
    var errorMessage: String?
    /// Neutral besked, fx "Tjek din e-mail".
    var infoMessage: String?

    private let authService: any AuthService

    init(authService: any AuthService) {
        self.authService = authService
    }

    /// Knappen er kun aktiv, når felterne ser rimelige ud.
    var canSubmit: Bool {
        !isWorking
            && isEmailValid
            && password.count >= Self.minimumPasswordLength
    }

    /// Samme slags tjek som Supabase: navn@domæne.endelse, uden mellemrum og kun almindelige tegn.
    /// (Supabase afviser fx "peter@test" og e-mails med æ, ø eller å.)
    var isEmailValid: Bool {
        trimmedEmail.wholeMatch(of: /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/) != nil
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Formular

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
        infoMessage = nil
    }

    /// Kaldes når brugeren trykker på knappen i formularen.
    func submit() async {
        guard canSubmit else { return }

        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }  // køres uanset hvordan funktionen slutter

        let credential = AuthCredential.email(address: trimmedEmail, password: password)

        do {
            switch mode {
            case .signIn:
                let session = try await authService.signIn(with: credential)
                finishSignIn(with: session)

            case .signUp:
                switch try await authService.signUp(with: credential) {
                case .signedIn(let session):
                    finishSignIn(with: session)
                case .confirmationRequired:
                    infoMessage = "We sent a confirmation email to \(trimmedEmail). Tap the link, then sign in."
                    mode = .signIn
                }
            }
        } catch {
            AppLog.shared.error("Auth: sign in/up failed", error)
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await authService.signOut()
            state = .signedOut
        } catch {
            AppLog.shared.error("Auth: sign out failed", error)
            errorMessage = "Couldn't sign out. Please try again."
        }
    }

    // MARK: - Hjælpere

    private func finishSignIn(with session: UserSession) {
        password = ""   // gem ikke adgangskoden længere end nødvendigt
        state = .signedIn(session)
    }

    /// Oversætter fejl til tekst, brugeren forstår.
    private static func message(for error: Error) -> String {
        switch error as? AuthServiceError {
        case .invalidCredentials:
            return "Wrong email or password."
        case .invalidEmail:
            return "That email address doesn't look right. Check it for typos, e.g. name@example.com."
        case .emailAlreadyInUse:
            return "There's already an account with that email. Try signing in."
        case .weakPassword:
            return "That password is too weak. Use at least \(minimumPasswordLength) characters."
        case .emailNotConfirmed:
            return "Please confirm your email before signing in."
        case .tooManyRequests:
            return "Too many attempts. Wait a moment and try again."
        case .network:
            return "No connection. Check your internet and try again."
        case .unknown, nil:
            return "Something went wrong. Please try again."
        }
    }
}
