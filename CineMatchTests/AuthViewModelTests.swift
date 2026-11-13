//
//  AuthViewModelTests.swift
//  CineMatchTests
//
//  Created by Peter Hannibal Hildorf on 09/10/2026.
//

import Testing
@testable import CineMatch

@MainActor
struct AuthViewModelTests {

    /// Laver en ViewModel med udfyldt, gyldig formular.
    private func makeViewModel(service: MockAuthService) -> AuthViewModel {
        let viewModel = AuthViewModel(authService: service)
        viewModel.email = "  peter@example.com "
        viewModel.password = "hemmelig123"
        return viewModel
    }

    @Test func startsInLoadingState() {
        let viewModel = AuthViewModel(authService: MockAuthService())
        #expect(viewModel.state == .loading)
    }

    @Test func restoreSessionWithoutStoredSessionIsSignedOut() async {
        let viewModel = AuthViewModel(authService: MockAuthService())

        await viewModel.restoreSession()

        #expect(viewModel.state == .signedOut)
    }

    @Test func restoreSessionWithStoredSessionIsSignedIn() async {
        let service = MockAuthService(storedSession: MockAuthService.sampleSession)
        let viewModel = AuthViewModel(authService: service)

        await viewModel.restoreSession()

        #expect(viewModel.state == .signedIn(MockAuthService.sampleSession))
    }

    @Test func cannotSubmitWithInvalidEmailOrShortPassword() {
        let viewModel = AuthViewModel(authService: MockAuthService())

        viewModel.email = "ikke-en-email"
        viewModel.password = "hemmelig123"
        #expect(viewModel.canSubmit == false)

        viewModel.email = "peter@example.com"
        viewModel.password = "123"
        #expect(viewModel.canSubmit == false)
    }

    @Test func signInSuccessTrimsEmailAndClearsPassword() async {
        let service = MockAuthService()
        let viewModel = makeViewModel(service: service)

        await viewModel.submit()

        #expect(viewModel.state == .signedIn(UserSession(userID: "mock-user-id", email: "peter@example.com")))
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.isWorking == false)
        #expect(service.signInCallCount == 1)
        #expect(service.signUpCallCount == 0)
    }

    @Test func signInWithWrongPasswordShowsFriendlyError() async {
        let service = MockAuthService(errorToThrow: AuthServiceError.invalidCredentials)
        let viewModel = makeViewModel(service: service)
        await viewModel.restoreSession()

        await viewModel.submit()

        #expect(viewModel.state == .signedOut)
        #expect(viewModel.errorMessage == "Forkert e-mail eller adgangskode.")
    }

    @Test func signUpSignsInWhenNoConfirmationNeeded() async {
        let service = MockAuthService()
        let viewModel = makeViewModel(service: service)
        viewModel.toggleMode()

        await viewModel.submit()

        #expect(service.signUpCallCount == 1)
        guard case .signedIn = viewModel.state else {
            Issue.record("Forventede signedIn, fik \(viewModel.state)")
            return
        }
    }

    @Test func signUpWithConfirmationShowsInfoAndSwitchesToSignIn() async {
        let service = MockAuthService()
        service.requiresEmailConfirmation = true
        let viewModel = makeViewModel(service: service)
        await viewModel.restoreSession()
        viewModel.toggleMode()

        await viewModel.submit()

        #expect(viewModel.state == .signedOut)
        #expect(viewModel.infoMessage != nil)
        #expect(viewModel.mode == .signIn)
    }

    @Test func signUpWithExistingEmailShowsError() async {
        let service = MockAuthService(errorToThrow: AuthServiceError.emailAlreadyInUse)
        let viewModel = makeViewModel(service: service)
        viewModel.toggleMode()

        await viewModel.submit()

        #expect(viewModel.errorMessage?.contains("findes allerede") == true)
    }

    @Test func signOutReturnsToSignedOut() async {
        let service = MockAuthService(storedSession: MockAuthService.sampleSession)
        let viewModel = AuthViewModel(authService: service)
        await viewModel.restoreSession()

        await viewModel.signOut()

        #expect(viewModel.state == .signedOut)
        #expect(service.signOutCallCount == 1)
        #expect(await service.currentSession() == nil)
    }

    @Test func signOutFailureKeepsUserSignedIn() async {
        let service = MockAuthService(storedSession: MockAuthService.sampleSession)
        let viewModel = AuthViewModel(authService: service)
        await viewModel.restoreSession()
        service.errorToThrow = AuthServiceError.network

        await viewModel.signOut()

        #expect(viewModel.state == .signedIn(MockAuthService.sampleSession))
        #expect(viewModel.errorMessage != nil)
    }
}
