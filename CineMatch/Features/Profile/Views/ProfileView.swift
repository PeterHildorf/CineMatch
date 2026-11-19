//
//  ProfileView.swift
//  CineMatch
//

import SwiftUI

/// Fanen "Profile": hvem du er, hvad du har bedømt, dine streamingtjenester, "Start fresh" og "Sign out".
/// Efter "Start fresh" foreslår vi at swipe igen eller søge, så anbefalingerne hurtigt kommer tilbage.
struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    let servicesViewModel: StreamingServicesViewModel
    /// Tjenesterne er gemt → Recommendations skal vise de nye.
    let onServicesChanged: () -> Void
    /// Dommene er slettet → de andre faner skal glemme dem.
    let onStartedFresh: () async -> Void
    let onSwipe: () -> Void
    let onSearch: () -> Void
    let onSignOut: () -> Void

    @State private var isShowingServices = false
    @State private var isConfirmingReset = false
    @State private var isConfirmingSignOut = false
    @State private var isShowingFreshStart = false

    var body: some View {
        List {
            header
            servicesSection
            dataSection
            accountSection
        }
        .navigationTitle("Profile")
        .task {
            await viewModel.load()
            await servicesViewModel.load()
        }
        .refreshable { await viewModel.load() }
        // Lukkes arket uden "Save", viser rækken stadig det gemte valg.
        .sheet(isPresented: $isShowingServices, onDismiss: { Task { await servicesViewModel.load() } }) {
            StreamingServicesView(viewModel: servicesViewModel, onSaved: onServicesChanged)
        }
        .sheet(isPresented: $isShowingFreshStart) {
            FreshStartSheet(
                onSwipe: { isShowingFreshStart = false; onSwipe() },
                onSearch: { isShowingFreshStart = false; onSearch() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Start fresh?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Delete all my ratings", role: .destructive) {
                Task {
                    guard await viewModel.startFresh() else { return }
                    await onStartedFresh()
                    isShowingFreshStart = true
                }
            }
        } message: {
            Text("This deletes your \(viewModel.ratedCount) ratings and today's pick. Your recommendations start over. This can't be undone.")
        }
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: onSignOut)
        }
    }

    // MARK: - Sektioner

    /// Avatar, e-mail og tre tal.
    private var header: some View {
        Section {
            VStack(spacing: 16) {
                Text(viewModel.initial)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(
                        LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                if let email = viewModel.email {
                    Text(email)
                        .font(.headline)
                }

                HStack(spacing: 10) {
                    StatTile(value: viewModel.ratedCount, label: "Rated", systemImage: "film")
                    StatTile(value: viewModel.lovedCount, label: "Loved", systemImage: "heart.fill")
                    StatTile(value: viewModel.streak, label: "Day streak", systemImage: "flame.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var servicesSection: some View {
        Section {
            Button { isShowingServices = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.tv")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My streaming services")
                            .foregroundStyle(.primary)
                        Text(servicesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Streaming")
        } footer: {
            Text("We show where you can watch each pick, and \"Only my services\" uses this list.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) { isConfirmingReset = true } label: {
                HStack {
                    Label("Start fresh", systemImage: "arrow.counterclockwise")
                    Spacer()
                    if viewModel.isResetting { ProgressView() }
                }
            }
            .disabled(!viewModel.hasRatings || viewModel.isResetting)

            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }
        } header: {
            Text("Your taste")
        } footer: {
            Text("Deletes all your ratings from Swipe and Search, so your recommendations start over. Your streaming services are kept.")
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) { isConfirmingSignOut = true } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Account")
        } footer: {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("CineMatch \(version)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
        }
    }

    /// Fx "Netflix, Disney+ and HBO Max" eller "None selected".
    private var servicesSummary: String {
        let names = servicesViewModel.services
            .filter { servicesViewModel.isSelected($0) }
            .map(\.name)
        return names.isEmpty ? "None selected" : names.formatted(.list(type: .and))
    }
}

/// Ét tal i headeren, fx "42 Rated".
private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text(value, format: .number)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .animation(.default, value: value)
    }
}

/// Vises efter "Start fresh": to veje til nye anbefalinger.
private struct FreshStartSheet: View {
    let onSwipe: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, options: .nonRepeating)

            VStack(spacing: 8) {
                Text("A fresh start")
                    .font(.title2.bold())
                Text("\(TasteInput.likes.requirementText), and your picks come back. Swipe through popular movies, or search for the ones you already know you love.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: onSwipe) {
                    Label("Start swiping", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onSearch) {
                    Label("Search for movies", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(24)
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            viewModel: ProfileViewModel(
                email: "anna@example.com",
                signalServices: [MockTasteSignalService(signals: [
                    TasteSignal(movieID: 318, verdict: .fantastic),
                    TasteSignal(movieID: 2571, verdict: .great),
                    TasteSignal(movieID: 1, verdict: .bad),
                ])],
                dailyPicks: DailyPickStore(defaults: UserDefaults(suiteName: "preview.profile")!, key: "preview")
            ),
            servicesViewModel: StreamingServicesViewModel(
                preferencesService: MockPreferencesService(stored: StreamingPreferences(services: [.netflix, .tv2Play]))
            ),
            onServicesChanged: {},
            onStartedFresh: {},
            onSwipe: {},
            onSearch: {},
            onSignOut: {}
        )
    }
}
