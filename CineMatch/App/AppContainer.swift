//
//  AppContainer.swift
//  CineMatch
//

import Foundation
import Supabase

/// Det ENESTE sted, hvor services oprettes. Views og ViewModels får dem injiceret.
///
/// Alle bedømmelser bruger samme skala (`Verdict`: 0/1/2/3/5). Pipelines:
/// - `swipe`: Swipe, Search og Today → Antons model. Film-id er Letterboxd-id.
///   Swipe og Search gemmer i samme bunke, så Today ændrer sig, uanset hvor brugeren bedømmer.
/// - `stars`: Mikkels model (TMDB-id). Ikke i UI'et lige nu (Rate og Star picks er fjernet).
///   TODO: Fodr den med swipe-dommene oversat Letterboxd-id → TMDB-id, så Today kan skifte model.
@MainActor
final class AppContainer {
    /// Én models data: film, brugerens svar og anbefalinger.
    struct ModelPipeline {
        let movieDataService: any MovieDataService
        let signalService: any TasteSignalService
        let recommendationService: any RecommendationService
        /// Logger visninger og "Seen it", så modellens præcision kan måles.
        var eventLogger: any RecommendationEventLogger = MockRecommendationEventLogger()
    }

    let authService: any AuthService
    let stars: ModelPipeline
    let swipe: ModelPipeline
    /// Plakater og streamingtjenester (TMDB).
    let mediaService: any TitleMediaService
    /// Streamingtjenester og andre indstillinger.
    let preferencesService: any PreferencesService
    /// Launch-argumentet `-freshUser`: start som en helt ny testbruger hver gang (se `resetToFreshTestUser()`).
    var startsAsFreshTestUser = false

    init(
        authService: any AuthService,
        stars: ModelPipeline,
        swipe: ModelPipeline,
        mediaService: any TitleMediaService = MockTitleMediaService(),
        preferencesService: any PreferencesService = MockPreferencesService()
    ) {
        self.authService = authService
        self.stars = stars
        self.swipe = swipe
        self.mediaService = mediaService
        self.preferencesService = preferencesService
    }

    /// Rigtige services, hvis Secrets.plist og modelfilerne findes – ellers mocks.
    static func live() -> AppContainer {
        // TMDB-nøglen ligger i Secrets.plist. Mangler den, vises pladsholdere i stedet for plakater.
        let mediaService: any TitleMediaService = TMDBConfig.load()
            .map { TMDBMediaService(credential: $0.credential) } ?? MockTitleMediaService()
        // Én klient til både login og data, så de deler session.
        let client = SupabaseConfig.load().map { SupabaseClient(supabaseURL: $0.url, supabaseKey: $0.anonKey) }
        let authService: any AuthService = client.map { SupabaseAuthService(client: $0) } ?? MockAuthService()

        let antonStore: ModelStore? = ModelStore.isAvailable() ? ModelStore() : nil

        // Så loggen viser, hvilke rigtige services og modeller appen kører med.
        AppLog.shared.info([
            "Supabase: \(client == nil ? "missing (mocks)" : "configured")",
            "TMDB: \(mediaService is TMDBMediaService ? "configured" : "missing (placeholders)")",
            "Anton model: \(antonStore == nil ? "missing (mocks)" : "available")",
            "MF model: \(MFModelStore.isAvailable() ? "available" : "missing (mocks)")",
        ].joined(separator: " · "))

        let container = AppContainer(
            authService: authService,
            stars: starPipeline(storage: Storage(client: client, pipeline: .stars)),
            swipe: antonPipeline(store: antonStore, storage: Storage(client: client, pipeline: .swipe)),
            mediaService: mediaService,
            preferencesService: LocalPreferencesService()
        )
        container.startsAsFreshTestUser = ProcessInfo.processInfo.arguments.contains("-freshUser")
        return container
    }

    /// Hvor én pipelines svar og målinger gemmes: Supabase, hvis Secrets.plist er sat op,
    /// ellers kun i hukommelsen (forsvinder, når appen lukkes).
    private struct Storage {
        let signals: any TasteSignalService
        let eventLogger: any RecommendationEventLogger

        init(client: SupabaseClient?, pipeline: PipelineID) {
            guard let client else {
                signals = MockTasteSignalService()
                eventLogger = MockRecommendationEventLogger()
                return
            }
            signals = SupabaseTasteSignalService(client: client, pipeline: pipeline)
            eventLogger = SupabaseRecommendationEventLogger(client: client, pipeline: pipeline)
        }
    }

    /// Mikkels model, hvis `cinematch_mf.json` ligger i appen. Ellers falske anbefalinger.
    private static func starPipeline(storage: Storage) -> ModelPipeline {
        let signals = storage.signals
        guard MFModelStore.isAvailable() else {
            return ModelPipeline(
                movieDataService: LocalJSONMovieDataService(),
                signalService: signals,
                recommendationService: MockRecommendationService(delay: .seconds(2)),
                eventLogger: storage.eventLogger
            )
        }
        let store = MFModelStore()
        return ModelPipeline(
            movieDataService: MFMovieDataService(store: store),
            signalService: signals,
            recommendationService: MFRecommendationService(store: store, tasteSignalService: signals),
            eventLogger: storage.eventLogger
        )
    }

    /// Én Anton-pipeline med sin egen like-bunke. Får modellen udefra, så flere pipelines (swipe, søgning)
    /// kan dele samme indlæste modelfil, men stadig have hvert sit input og hvert sit resultat.
    /// `store == nil` (modelfilen mangler) → falske anbefalinger.
    private static func antonPipeline(store: ModelStore?, storage: Storage) -> ModelPipeline {
        let signals = storage.signals
        guard let store else {
            return ModelPipeline(
                movieDataService: LocalJSONMovieDataService(),
                signalService: signals,
                recommendationService: MockRecommendationService(delay: .seconds(2)),
                eventLogger: storage.eventLogger
            )
        }
        return ModelPipeline(
            movieDataService: OnDeviceMovieDataService(store: store),
            signalService: signals,
            recommendationService: OnDeviceRecommendationService(store: store, tasteSignalService: signals),
            eventLogger: storage.eventLogger
        )
    }

    /// `-freshUser`: logger ud, logger ind som testbrugeren og sletter alt, han har gjort,
    /// så appen opfører sig som første gang (tjenester → Swipe-onboarding → Recommendations).
    /// Rører kun testbrugeren fra Secrets.plist – aldrig den bruger, der var logget ind før.
    /// Målinger (`recommendation_*`) kan appen ikke slette (RLS); de ligger under testbrugerens id.
    func resetToFreshTestUser() async {
        // Altid ud først: så ender man aldrig stille og roligt på sin egen konto, hvis noget mangler.
        try? await authService.signOut()
        guard let testUser = TestUserConfig.load() else {
            AppLog.shared.info("-freshUser: add TEST_USER_EMAIL and TEST_USER_PASSWORD to Secrets.plist – showing sign-in")
            return
        }
        do {
            _ = try await authService.signIn(with: .email(address: testUser.email, password: testUser.password))
        } catch {
            AppLog.shared.error("-freshUser: couldn't sign in as \(testUser.email)", error)
            return
        }
        for pipeline in [stars, swipe] {
            do {
                try await pipeline.signalService.deleteAllSignals()
            } catch {
                AppLog.shared.error("-freshUser: couldn't delete answers", error)
            }
        }
        // Lokalt gemt: streamingtjenester og "Today's pick"/streak.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key == "streamingPreferences" || key.hasPrefix("dailyPick.") {
            defaults.removeObject(forKey: key)
        }
        AppLog.shared.info("-freshUser: signed in as \(testUser.email) with no answers")
    }

    /// Hele appen med mockdata (`DemoData`), så UI'et kan ses uden modelfiler og Supabase.
    /// Start appen med launch-argumentet `-demo` (Edit Scheme → Run → Arguments).
    /// Med TMDB-nøgle i Secrets.plist vises rigtige plakater, ellers pladsholdere.
    static func demo() -> AppContainer {
        let mediaService: any TitleMediaService = TMDBConfig.load()
            .map { TMDBMediaService(credential: $0.credential) } ?? MockTitleMediaService.demo
        func pipeline() -> ModelPipeline {
            let signals = MockTasteSignalService()
            return ModelPipeline(
                movieDataService: MockMovieDataService(titles: DemoData.swipeTitles, catalog: DemoData.titles),
                signalService: signals,
                recommendationService: MockRecommendationService(
                    nextResult: DemoData.recommendations, delay: .seconds(1), tasteSignalService: signals
                )
            )
        }
        AppLog.shared.info("Demo mode: mock data, no Supabase or model files")
        return AppContainer(
            authService: MockAuthService(storedSession: MockAuthService.sampleSession),
            stars: pipeline(),
            swipe: pipeline(),
            mediaService: mediaService,
            preferencesService: MockPreferencesService()
        )
    }

    /// Kun falske services – til previews og tests.
    static func mock(signedIn: Bool = false) -> AppContainer {
        AppContainer(
            authService: MockAuthService(storedSession: signedIn ? MockAuthService.sampleSession : nil),
            stars: ModelPipeline(
                movieDataService: MockMovieDataService(),
                signalService: MockTasteSignalService(),
                recommendationService: MockRecommendationService(delay: .seconds(1))
            ),
            swipe: ModelPipeline(
                movieDataService: MockMovieDataService(),
                signalService: MockTasteSignalService(),
                recommendationService: MockRecommendationService(delay: .seconds(1))
            )
        )
    }
}
