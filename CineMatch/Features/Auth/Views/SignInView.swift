//
//  SignInView.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import AuthenticationServices
import SwiftUI


struct SignInView: View {
    let viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading){
            Text("CineMatch")
                .font(.system(size: 60, weight: .ultraLight))


            Text("Movies & TV-Shows based on your taste, with reasons and explanations")

            Spacer() // UI detaljer skal tilføjes i dette rum

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            // Viewet sender kun brugerens handling videre – ViewModel'en gør arbejdet.
            SignInWithAppleButton(.signIn) { request in
                viewModel.prepare(request)
            } onCompletion: { result in
                Task { await viewModel.handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(.whiteOutline)// .white, .whiteOutline
            .frame(height: 50)
            .disabled(viewModel.isWorking)

            // Kun synlig med MockAuthService, så du kan teste i Simulatoren uden Apple-ID.
            if viewModel.allowsTestSignIn {
                Button("Log ind som testbruger") {
                    Task { await viewModel.signInAsTestUser() }
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isWorking)
            }

            Text("Your account will be connected to your apple account, and secured safely. We do not share data")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay {
            if viewModel.isWorking {
                ProgressView()
            }
        }
    }

}

#Preview {
    SignInView(viewModel: AuthViewModel(authService: MockAuthService(), allowsTestSignIn: true))
}
