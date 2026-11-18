//
//  RootView.swift
//  CineMatch
//

import SwiftUI

/// Bestemmer hvilken skærm der vises ud fra login-tilstanden.
struct RootView: View {
    // Ingen startværdi her: @State er en macro i iOS 27, så den sættes kun i init.
    @State private var authViewModel: AuthViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        authViewModel = AuthViewModel(authService: container.authService)
    }

    var body: some View {
        Group {
            switch authViewModel.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView(viewModel: authViewModel)
            case .signedIn(let session):
                MainTabView(container: container, session: session) {
                    Task { await authViewModel.signOut() }
                }
            }
        }
        .task {
            if container.startsAsFreshTestUser {
                await container.resetToFreshTestUser()
            }
            await authViewModel.restoreSession()
        }
    }
}

#Preview("Logget ud") {
    RootView(container: .mock())
}

#Preview("Logget ind") {
    RootView(container: .mock(signedIn: true))
}

