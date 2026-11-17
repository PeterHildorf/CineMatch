//
//  AppContainer.swift
//  CineMatch
//

import Foundation
import Supabase

/// Det ENESTE sted, hvor services oprettes. Views og ViewModels får dem injiceret.
///
/// Appen kører to modeller side om side, så de kan sammenlignes:
/// - `stars`: stjerner (½–5) → Mikkels model. Film-id er TMDB-id.
/// - `swipe`: like/dislike → Antons model. Film-id er Letterboxd-id.
/// De har hver deres svar, fordi de bruger forskellige film-id'er.
@MainActor
final class AppContainer {
    /// Én models data: film, brugerens svar og anbefalinger.
    struct ModelPipeline {
        let movieDataService: any MovieDataService
        let signalService: any TasteSignalService
        let recommendationService: any RecommendationService
    }

    let authService: any AuthService
    let stars: ModelPipeline
    let swipe: ModelPipeline
    /// Antons model igen, men med sin EGEN like-bunke. Søgning bruger den, så swipe og søgning
    /// ikke påvirker hinanden og hver får sit eget anbefalingsresultat ("Search picks").
    let search: ModelPipeline
    /// Plakater og streamingtjenester (TMDB).
    let mediaService: any TitleMediaService
    /// Streamingtjenester og andre indstillinger.
    let preferencesService: any PreferencesService

    init(
        authService: any AuthService,
        stars: ModelPipeline,
        swipe: ModelPipeline,
        search: ModelPipeline,
        mediaService: any TitleMediaService = MockTitleMediaService(),
        preferencesService: any PreferencesService = MockPreferencesService()
    ) {
        self.authService = authService
        self.stars = stars
        self.swipe = swipe
        self.search = search
        self.mediaService = mediaService
        self.preferencesService = preferencesService
    }

    /// Rigtige services, hvis Secrets.plist og modelfilerne findes – ellers mocks.
    static func live() -> AppContainer {
        // TMDB-nøglen ligger i Secrets.plist. Mangler den, vises pladsholdere i stedet for plakater.
        let mediaService: any TitleMediaService = TMDBConfig.load()
            .map { TMDBMediaService(credential: $0.credential) } ?? MockTitleMediaService()
        let authService: any AuthService = SupabaseConfig.load()
            .map { SupabaseAuthService(client: SupabaseClient(supabaseURL: $0.url, supabaseKey: $0.anonKey)) }
            ?? MockAuthService()

        // Én delt modelfil (actor), så Antons model kun loades én gang, selv om swipe og søgning
        // har hver sin like-bunke og hver sit anbefalingsresultat.
        let antonStore: ModelStore? = ModelStore.isAvailable() ? ModelStore() : nil

        return AppContainer(
            authService: authService,
            stars: starPipeline(),
            swipe: antonPipeline(store: antonStore),
            search: antonPipeline(store: antonStore),
            mediaService: mediaService,
            preferencesService: LocalPreferencesService()
        )
    }

    // TODO: Supabase-versioner af svarene (tabellen taste_signals), så de gemmes under brugeren.
    // Indtil da gemmes de kun i hukommelsen (forsvinder, når appen lukkes).

    /// Mikkels model, hvis `cinematch_mf.json` ligger i appen. Ellers falske anbefalinger.
    private static func starPipeline() -> ModelPipeline {
        let signals = MockTasteSignalService()
        guard MFModelStore.isAvailable() else {
            return ModelPipeline(
                movieDataService: LocalJSONMovieDataService(),
                signalService: signals,
                recommendationService: MockRecommendationService(delay: .seconds(2))
            )
        }
        let store = MFModelStore()
        return ModelPipeline(
            movieDataService: MFMovieDataService(store: store),
            signalService: signals,
            recommendationService: MFRecommendationService(store: store, tasteSignalService: signals)
        )
    }

    /// Én Anton-pipeline med sin egen like-bunke. Får modellen udefra, så flere pipelines (swipe, søgning)
    /// kan dele samme indlæste modelfil, men stadig have hvert sit input og hvert sit resultat.
    /// `store == nil` (modelfilen mangler) → falske anbefalinger.
    private static func antonPipeline(store: ModelStore?) -> ModelPipeline {
        let signals = MockTasteSignalService()
        guard let store else {
            return ModelPipeline(
                movieDataService: LocalJSONMovieDataService(),
                signalService: signals,
                recommendationService: MockRecommendationService(delay: .seconds(2))
            )
        }
        return ModelPipeline(
            movieDataService: OnDeviceMovieDataService(store: store),
            signalService: signals,
            recommendationService: OnDeviceRecommendationService(store: store, tasteSignalService: signals)
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
            ),
            search: ModelPipeline(
                movieDataService: MockMovieDataService(),
                signalService: MockTasteSignalService(),
                recommendationService: MockRecommendationService(delay: .seconds(1))
            )
        )
    }
}
