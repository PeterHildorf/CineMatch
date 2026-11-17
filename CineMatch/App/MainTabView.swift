//
//  MainTabView.swift
//  CineMatch
//

import SwiftUI

/// Hovedskærmen efter login.
///
/// Først et onboarding-flow: streamingtjenester → stjerner (Mikkels model) → swipe (Antons model).
/// Derefter fire faner, så de to modeller kan sammenlignes:
/// "Rate" og "Star picks" (Mikkel) · "Swipe" og "Swipe picks" (Anton).
struct MainTabView: View {
    enum Step: Equatable {
        case checking
        case services
        case rating
        case swipe
        case done
    }

    let session: UserSession
    let onSignOut: () -> Void

    // Ingen startværdi her: @State er en macro i iOS 27, så den sættes kun i init.
    @State private var step: Step
    @State private var ratingViewModel: RatingViewModel
    @State private var tasteViewModel: TasteViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var starPicksViewModel: RecommendationsViewModel
    @State private var swipePicksViewModel: RecommendationsViewModel
    @State private var searchPicksViewModel: RecommendationsViewModel
    @State private var servicesViewModel: StreamingServicesViewModel
    @State private var isShowingServices: Bool

    init(container: AppContainer, session: UserSession, onSignOut: @escaping () -> Void) {
        self.session = session
        self.onSignOut = onSignOut
        step = .checking
        isShowingServices = false
        ratingViewModel = RatingViewModel(
            movieDataService: container.stars.movieDataService,
            signalService: container.stars.signalService,
            mediaService: container.mediaService
        )
        tasteViewModel = TasteViewModel(
            movieDataService: container.swipe.movieDataService,
            tasteSignalService: container.swipe.signalService,
            mediaService: container.mediaService,
            input: .likes
        )
        // Søgning har sin egen Anton-pipeline (egen like-bunke), adskilt fra Swipe.
        searchViewModel = SearchViewModel(
            movieDataService: container.search.movieDataService,
            signalService: container.search.signalService,
            mediaService: container.mediaService
        )
        // Ingen "Seen it" og ingen målinger på Star picks endnu: det er ikke afgjort, hvordan like/dislike
        // skal blive til stjerner. Visninger uden feedback ville se ud som 0 % seen-rate i sammenligningen.
        starPicksViewModel = RecommendationsViewModel(
            recommendationService: container.stars.recommendationService,
            movieDataService: container.stars.movieDataService,
            mediaService: container.mediaService,
            preferencesService: container.preferencesService,
            input: .starRatings,
            title: "Star picks"
        )
        swipePicksViewModel = RecommendationsViewModel(
            recommendationService: container.swipe.recommendationService,
            movieDataService: container.swipe.movieDataService,
            mediaService: container.mediaService,
            preferencesService: container.preferencesService,
            signalService: container.swipe.signalService,
            eventLogger: container.swipe.eventLogger,
            input: .likes,
            title: "Swipe picks"
        )
        searchPicksViewModel = RecommendationsViewModel(
            recommendationService: container.search.recommendationService,
            movieDataService: container.search.movieDataService,
            mediaService: container.mediaService,
            preferencesService: container.preferencesService,
            signalService: container.search.signalService,
            eventLogger: container.search.eventLogger,
            input: .likes,
            title: "Search picks"
        )
        servicesViewModel = StreamingServicesViewModel(preferencesService: container.preferencesService)
    }

    var body: some View {
        Group {
            switch step {
            case .checking:
                ProgressView()
                    .task { step = await servicesViewModel.needsSetup() ? .services : .rating }
            case .services:
                StreamingServicesView(viewModel: servicesViewModel) {
                    servicesChanged()
                    step = .rating
                }
            case .rating:
                NavigationStack {
                    RatingView(viewModel: ratingViewModel)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Continue") { step = .swipe }
                                    .disabled(!ratingViewModel.hasEnoughRatings)
                            }
                        }
                }
            case .swipe:
                NavigationStack {
                    TasteView(viewModel: tasteViewModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Back") { step = .rating }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { step = .done }
                                    .disabled(!tasteViewModel.hasEnoughLikes)
                            }
                        }
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
        TabView {
            Tab("Rate", systemImage: "star") {
                NavigationStack {
                    RatingView(viewModel: ratingViewModel)
                        .toolbar { accountMenu }
                }
            }
            Tab("Star picks", systemImage: "sparkles") {
                NavigationStack {
                    RecommendationsView(viewModel: starPicksViewModel)
                        .toolbar { accountMenu }
                }
            }
            Tab("Swipe", systemImage: "hand.thumbsup") {
                NavigationStack {
                    TasteView(viewModel: tasteViewModel)
                        .toolbar { accountMenu }
                }
            }
            Tab("Swipe picks", systemImage: "rectangle.stack") {
                NavigationStack {
                    RecommendationsView(viewModel: swipePicksViewModel)
                        .toolbar { accountMenu }
                }
            }
            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack {
                    SearchView(viewModel: searchViewModel)
                        .toolbar { accountMenu }
                }
            }
            Tab("Search picks", systemImage: "wand.and.stars") {
                NavigationStack {
                    RecommendationsView(viewModel: searchPicksViewModel)
                        .toolbar { accountMenu }
                }
            }
        }
    }

    /// Alle resultatsider skal vise de nye tjenester.
    private func servicesChanged() {
        Task {
            await starPicksViewModel.preferencesChanged()
            await swipePicksViewModel.preferencesChanged()
            await searchPicksViewModel.preferencesChanged()
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
    MainTabView(container: .mock(signedIn: true), session: MockAuthService.sampleSession) {}
}
