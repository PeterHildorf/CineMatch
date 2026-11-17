//
//  SignInView.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import SwiftUI


struct SignInView: View {
    // @Bindable gør det muligt at binde felterne ($viewModel.email) til en @Observable klasse.
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading){
            Text("CineMatch")
                .font(.system(size: 60, weight: .ultraLight))


            Text("Movies & TV-Shows based on your taste, with reasons and explanations")

            Spacer() // UI detaljer skal tilføjes i dette rum

            VStack(spacing: 12) {
                TextField("E-mail", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Adgangskode (mindst \(AuthViewModel.minimumPasswordLength) tegn)", text: $viewModel.password)
                    .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isWorking)

            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }

            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Viewet sender kun brugerens handling videre – ViewModel'en gør arbejdet.
            Button {
                Task { await viewModel.submit() }
            } label: {
                Group {
                    if viewModel.isWorking {
                        ProgressView()
                    } else {
                        Text(viewModel.mode == .signIn ? "Log ind" : "Opret konto")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)

            Button(viewModel.mode == .signIn ? "Ny bruger? Opret en konto" : "Har du en konto? Log ind") {
                viewModel.toggleMode()
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isWorking)

            Text("Your account will be secured safely. We do not share data")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

}

#Preview {
    SignInView(viewModel: AuthViewModel(authService: MockAuthService()))
}
