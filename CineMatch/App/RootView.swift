//
//  RootView.swift
//  CineMatch
//

import SwiftUI

/// Bestemmer hvilken skærm der vises ud fra login-tilstanden.
struct RootView: View {
    // Ingen startværdi her: @State er en macro i iOS 27, så den sættes kun i init.
    @State private var authViewModel: AuthViewModel

    init(container: AppContainer) {
        authViewModel = AuthViewModel(
            authService: container.authService,
            allowsTestSignIn: container.usesMockServices
        )
    }

    var body: some View {
        Group {
            switch authViewModel.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView(viewModel: authViewModel)
            case .signedIn(let session):
                SignedInPlaceholderView(session: session) {
                    Task { await authViewModel.signOut() }
                }
            }
        }
        .task {
            await authViewModel.restoreSession()
        }
    }
}

/// Midlertidig hovedskærm, indtil onboarding og anbefalinger er bygget (Fase 3–4).
private struct SignedInPlaceholderView: View {
    let session: UserSession
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Velkommen\(session.displayName.map { ", \($0)" } ?? "")!")
                .font(.title)
            Text("Bruger-id: \(session.userID)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Log ud", role: .destructive, action: onSignOut)
        }
        .padding()
    }
}

#Preview("Logget ud") {
    RootView(container: .mock())
}

#Preview("Logget ind") {
    RootView(container: .mock(signedIn: true))
}
