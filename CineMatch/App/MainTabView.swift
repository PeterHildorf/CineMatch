//
//  MainTabView.swift
//  CineMatch
//

import SwiftUI

/// Hovedskærmen efter login.
///
/// Første gang: streamingtjenester → Swipe med en kort guide. Efter 10 film (og 5 Great/Fantastic)
/// kommer "Your picks are ready" → Today, hvor de første anbefalinger regnes.
/// Derefter (og ved alle senere åbninger) direkte til fanerne: Today · Swipe · Search.
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
        case today, swipe, search
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
    @State private var isShowingServices: Bool
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
        isShowingServices = false
        isShowingPicksReady = false
        hasOfferedPicks = false
        swipeSignals = container.swipe.signalService
        tasteViewModel = TasteViewModel(
            movieDataService: container.swipe.movieDataService,
            tasteSignalService: container.swipe.signalService,
            mediaService: container.mediaService,
            input: .likes
        )
        // Søgning gemmer i samme bunke som Swipe, så Today også ændrer sig af søgninger.
        searchViewModel = SearchViewModel(
            movieDataService: container.swipe.movieDataService,
            signalService: container.swipe.signalService,
            mediaService: container.mediaService
        )
        // Today: Antons model på Swipe-dommene. Ny pick hver dag, beregnes selv, når brugeren har bedømt mere.
        todayViewModel = RecommendationsViewModel(
            recommendationService: container.swipe.recommendationService,
            movieDataService: container.swipe.movieDataService,
            mediaService: container.mediaService,
            preferencesService: container.preferencesService,
            signalService: container.swipe.signalService,
            eventLogger: container.swipe.eventLogger,
            dailyPicks: DailyPickStore(key: "dailyPick.swipe.\(session.userID)"),
            autoRecompute: true,
            input: .likes,
            title: "Recommendations"
        )
        servicesViewModel = StreamingServicesViewModel(preferencesService: container.preferencesService)
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
        .sheet(isPresented: $isShowingServices) {
            StreamingServicesView(viewModel: servicesViewModel) { servicesChanged() }
        }
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
                    }
                }
            }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            // Ingen overskrift eller kontomenu her: fanen viser navnet, og menuen findes i Swipe og Search.
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
                        .toolbar { accountMenu }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    SearchView(viewModel: searchViewModel)
                        .toolbar { accountMenu }
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

    /// Lille menu med e-mail, streamingtjenester og "Sign out" – samme i alle faner.
    private var accountMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu("Account", systemImage: "person.crop.circle") {
                if let email = session.email {
                    Text(email)
                }
                Button("My streaming services", systemImage: "play.tv") {
                    isShowingServices = true
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: onSignOut)
            }
        }
    }
}

#Preview {
    MainTabView(container: .demo(), session: MockAuthService.sampleSession) {}
}
