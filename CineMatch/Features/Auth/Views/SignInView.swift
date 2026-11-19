//
//  SignInView.swift
//  CineMatch
//
//  Created by Peter Hannibal Hildorf on 01/10/2026.
//

import SwiftUI

/// Log ind / opret konto. Én skærm til begge: man skifter øverst i formularen.
/// Store felter (56 pt) med ikon, tydelig markering af feltet, man skriver i, og en stor knap i temaets gradient.
struct SignInView: View {
    // @Bindable gør det muligt at binde felterne ($viewModel.email) til en @Observable klasse.
    @Bindable var viewModel: AuthViewModel

    @FocusState private var focus: Field?
    @State private var isShowingPassword = false

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                hero
                form
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .top) {
            // Svag teal-glød øverst, så skærmen ikke føles som en tom formular.
            LinearGradient(colors: [Theme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.mode)
    }

    // MARK: - Top

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Theme.gradient, in: .rect(cornerRadius: 24))
                .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
                .accessibilityHidden(true)

            Text("CineMatch")
                .font(.system(size: 40, weight: .bold, design: .rounded))

            Text("Movies based on your taste, with reasons and explanations")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    // MARK: - Formular

    private var form: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: modeBinding) {
                Text("Sign in").tag(AuthViewModel.Mode.signIn)
                Text("Create account").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .disabled(viewModel.isWorking)

            Text(viewModel.mode == .signIn
                 ? "Welcome back. Sign in to see your picks."
                 : "It takes less than a minute. Then we'll find movies you'll love.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)

            VStack(spacing: 12) {
                field(icon: "envelope", isFocused: focus == .email) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                }

                // Vises, når man har forladt feltet med en e-mail, der ikke kan bruges.
                if !viewModel.email.isEmpty, !viewModel.isEmailValid, focus != .email {
                    Label("Enter a valid email, e.g. name@example.com", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }

                field(icon: "lock", isFocused: focus == .password) {
                    Group {
                        if isShowingPassword {
                            TextField("Password", text: $viewModel.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Password", text: $viewModel.password)
                        }
                    }
                    .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)

                    Button {
                        isShowingPassword.toggle()
                    } label: {
                        Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
                }

                if viewModel.mode == .signUp {
                    Label("At least \(AuthViewModel.minimumPasswordLength) characters", systemImage: passwordLongEnough ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(passwordLongEnough ? Theme.accent : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
            .disabled(viewModel.isWorking)

            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }

            if let infoMessage = viewModel.infoMessage {
                Label(infoMessage, systemImage: "envelope.badge")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Viewet sender kun brugerens handling videre – ViewModel'en gør arbejdet.
            Button(action: submit) {
                if viewModel.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(viewModel.mode == .signIn ? "Sign in" : "Create account")
                }
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canSubmit)
            .padding(.top, 4)
        }
    }

    private var footer: some View {
        Label("Your account will be secured safely. We do not share data", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Dele

    /// Et stort felt med ikon til venstre. Får en teal kant, når man skriver i det.
    private func field<Content: View>(icon: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isFocused ? Theme.accent : .secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: Theme.fieldHeight)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Theme.fieldCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.fieldCornerRadius)
                .stroke(isFocused ? Theme.accent : .clear, lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var passwordLongEnough: Bool {
        viewModel.password.count >= AuthViewModel.minimumPasswordLength
    }

    /// Skifter mellem "Log ind" og "Opret konto" via view model'en, så beskeder nulstilles.
    private var modeBinding: Binding<AuthViewModel.Mode> {
        Binding(
            get: { viewModel.mode },
            set: { if $0 != viewModel.mode { viewModel.toggleMode() } }
        )
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        focus = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    SignInView(viewModel: AuthViewModel(authService: MockAuthService()))
        .tint(Theme.accent)
}
