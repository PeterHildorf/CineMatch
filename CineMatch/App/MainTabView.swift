//
//  MainTabView.swift
//  CineMatch
//

import SwiftUI

/// Hovedskærmen efter login.
///
/// Første gang: streamingtjenester → Swipe med en kort guide. Efter 10 film (og 5 Great/Fantastic)
/// kommer "Your picks are ready" → Today, hvor de første anbefalinger regnes.
/// Derefter (og ved alle senere åbninger) direkte til fanerne: Today · Swipe · Search · Profile.
///
/// Swipe og Search gemmer i samme bunke, så Today ændrer sig, hver gang brugeren bedømmer en film.
struct MainTabView: View {
    enum Step: Equatable {
        case checking
        case services
        case swipe
        case done
    }

    enum AppTab: Hashable {
        case today, swipe, search, profile
    }

    let session: UserSession
    let onSignOut: () -> Void

    // Ingen startværdi her: @State er en macro i iOS 27, så den sættes kun i init.
    @State private var step: Step
    @State private var selectedTab: AppTab
    @State private var tasteViewModel: TasteViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var todayViewModel: RecommendationsViewModel
    @State private var servicesViewModel: StreamingServicesViewModel
    @State private var profileViewModel: ProfileViewModel
    /// "Your picks are ready" efter 10 film i onboarding.
    @State private var isShowingPicksReady: Bool
    /// Så popuppen kun kommer én gang, også hvis brugeren vælger "Keep swiping".
    @State private var hasOfferedPicks: Bool
    private let swipeSignals: any TasteSignalService

    init(container: AppContainer, session: UserSession, onSignOut: @escaping () -> Void) {
        self.session = session
        self.onSignOut = onSignOut
        step = .checking
        selectedTab = .today
        isShowingPicksReady = false
        hasOfferedPicks = false
        swipeSignals = container.swipe.signalService
        let preferencesService = container.preferencesService(for: session.userID)
        // Delt mellem Today og Profile, så "Start fresh" også nulstiller dagens pick og streak.
        let dailyPicks = DailyPickStore(
            key: "dailyPick.\(container.swipe.dailyPickNamespace).\(session.userID)",
            legacyKey: container.swipe.legacyDailyPickNamespace.map { "dailyPick.\($0).\(session.userID)" }
        )
        tasteViewModel = TasteViewModel(
            movieDataService: container.swipe.movieDataService,
            tasteSignalService: container.swipe.signalService,
            mediaService: container.mediaService,
            input: .likes,
            order: { TasteViewModel.shuffledInBlocks($0) }
        )
        // Søgning gemmer i samme bunke som Swipe, så Today også ændrer sig af søgninger.
        searchViewModel = SearchViewModel(
            movieDataService: container.swipe.movieDataService,
            signalService: container.swipe.signalService,
            mediaService: container.mediaService
        )
        // Today shares the supported TMDB catalogue and numeric opinions with Swipe and Search.
        todayViewModel = RecommendationsViewModel(
            recommendationService: container.swipe.recommendationService,
            movieDataService: container.swipe.movieDataService,
            mediaService: container.mediaService,
            preferencesService: preferencesService,
            signalService: container.swipe.signalService,
            eventLogger: container.swipe.eventLogger,
            dailyPicks: dailyPicks,
            autoRecompute: true,
            input: .likes,
            title: "Recommendations"
        )
        servicesViewModel = StreamingServicesViewModel(preferencesService: preferencesService)
        // The active adapter resets canonical opinions and both legacy stores together.
        profileViewModel = ProfileViewModel(
            email: session.email,
            signalServices: [container.swipe.signalService],
            dailyPicks: dailyPicks
        )
    }

    var body: some View {
        Group {
            switch step {
            case .checking:
                ProgressView()
                    .task { step = await firstStep() }
            case .services:
                StreamingServicesView(viewModel: servicesViewModel) {
                    servicesChanged()
                    Task { step = await hasFinishedSwipe() ? .done : .swipe }
                }
            case .swipe:
                NavigationStack {
                    TasteView(viewModel: tasteViewModel, isOnboarding: true, finishedHint: "Tap Done to see your picks.")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: showPicks)
                                    .disabled(!tasteViewModel.hasEnoughLikes)
                            }
                        }
                }
                .onChange(of: tasteViewModel.answeredCount) {
                    guard tasteViewModel.isReadyForPicks, !hasOfferedPicks else { return }
                    hasOfferedPicks = true
                    isShowingPicksReady = true
                }
                .alert("Your picks are ready", isPresented: $isShowingPicksReady) {
                    Button("Show my picks", action: showPicks)
                    Button("Keep swiping", role: .cancel) {}
                } message: {
                    Text("We know enough about your taste to find movies for you. The more you rate, the sharper your picks get.")
                }
            case .done:
                tabs
            }
        }
        .animation(.default, value: step)
    }

    private var tabs: some View {
        tabView
            // Svar i én fane skal ses i de andre: Today regner nyt, Swipe fjerner film bedømt i Search.
            .onChange(of: selectedTab) { _, tab in
                Task {
                    switch tab {
                    case .today: await todayViewModel.refresh()
                    case .swipe: await tasteViewModel.syncAnswers()
                    case .search: await searchViewModel.loadVerdicts()
                    case .profile: await profileViewModel.load()
                    }
                }
            }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Recommendations", systemImage: "sparkles", value: .today) {
                NavigationStack {
                    TodayView(
                        viewModel: todayViewModel,
                        onSwipeMore: { selectedTab = .swipe },
                        onSearch: { selectedTab = .search }
                    )
                }
            }
            Tab("Swipe", systemImage: "rectangle.stack", value: .swipe) {
                NavigationStack {
                    TasteView(viewModel: tasteViewModel)
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    // Ny Search med rækker af plakater. Den gamle liste: `SearchView(viewModel: searchViewModel)`.
                    SearchShelvesView(viewModel: searchViewModel)
                }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                NavigationStack {
                    ProfileView(
                        viewModel: profileViewModel,
                        servicesViewModel: servicesViewModel,
                        onServicesChanged: servicesChanged,
                        onStartedFresh: startedFresh,
                        onSwipe: { selectedTab = .swipe },
                        onSearch: { selectedTab = .search },
                        onSignOut: onSignOut
                    )
                }
            }
        }
    }

    // MARK: - Flow

    /// Onboarding færdig → Today, som regner de første anbefalinger.
    private func showPicks() {
        selectedTab = .today
        step = .done
    }

    /// Tjenester først, hvis de mangler. Kender modellen allerede brugerens smag, går vi direkte til fanerne.
    private func firstStep() async -> Step {
        if await servicesViewModel.needsSetup() { return .services }
        return await hasFinishedSwipe() ? .done : .swipe
    }

    /// Nok Great/Fantastic i Swipe til, at Today kan vise anbefalinger.
    private func hasFinishedSwipe() async -> Bool {
        let signals = (try? await swipeSignals.allSignals()) ?? []
        return signals.likedMovieIDs.count >= TasteViewModel.minimumLikes
    }

    /// Alle resultatsider skal vise de nye tjenester.
    private func servicesChanged() {
        Task {
            await todayViewModel.preferencesChanged()
        }
    }

    /// "Start fresh" i Profile: alle faner glemmer de gamle domme og anbefalinger.
    private func startedFresh() async {
        await todayViewModel.startOver()
        await tasteViewModel.load()
        await searchViewModel.loadVerdicts()
    }
}

#Preview {
    MainTabView(container: .demo(), session: MockAuthService.sampleSession) {}
}
