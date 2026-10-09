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
    private struct TestError: Error {}

    private let appleCredential = AuthCredential.apple(
        idToken: "token",
        rawNonce: "nonce",
        fullName: "Peter Hansen",
        email: "peter@example.com"
    )

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

    @Test func signInSuccessSetsSignedInWithNameAndEmail() async {
        let service = MockAuthService()
        let viewModel = AuthViewModel(authService: service)

        await viewModel.signIn(with: appleCredential)

        guard case .signedIn(let session) = viewModel.state else {
            Issue.record("Forventede signedIn, fik \(viewModel.state)")
            return
        }
        #expect(session.displayName == "Peter Hansen")
        #expect(session.email == "peter@example.com")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isWorking == false)
        #expect(service.signInCallCount == 1)
    }

    @Test func signInFailureShowsErrorAndStaysSignedOut() async {
        let service = MockAuthService(errorToThrow: TestError())
        let viewModel = AuthViewModel(authService: service)
        await viewModel.restoreSession()

        await viewModel.signIn(with: appleCredential)

        #expect(viewModel.state == .signedOut)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isWorking == false)
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
        service.errorToThrow = TestError()

        await viewModel.signOut()

        #expect(viewModel.state == .signedIn(MockAuthService.sampleSession))
        #expect(viewModel.errorMessage != nil)
    }

}
