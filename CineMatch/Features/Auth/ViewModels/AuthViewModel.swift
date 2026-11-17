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
            && trimmedEmail.contains("@")
            && password.count >= Self.minimumPasswordLength
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
                    infoMessage = "Vi har sendt en bekræftelsesmail til \(trimmedEmail). Klik på linket, og log derefter ind."
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
            errorMessage = "Kunne ikke logge ud. Prøv igen."
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
            return "Forkert e-mail eller adgangskode."
        case .emailAlreadyInUse:
            return "Der findes allerede en konto med den e-mail. Prøv at logge ind."
        case .weakPassword:
            return "Adgangskoden er for svag. Brug mindst \(minimumPasswordLength) tegn."
        case .emailNotConfirmed:
            return "Du skal bekræfte din e-mail, før du kan logge ind."
        case .tooManyRequests:
            return "For mange forsøg. Vent lidt, og prøv igen."
        case .network:
            return "Ingen forbindelse. Tjek dit internet, og prøv igen."
        case .unknown, nil:
            return "Noget gik galt. Prøv igen."
        }
    }
}
