//
//  AppContainer.swift
//  CineMatch
//

import Foundation
import Supabase

/// Det ENESTE sted, hvor services oprettes. Views og ViewModels får dem injiceret.
/// Flere services (MovieDataService, TasteProfileStore, …) tilføjes her i de næste faser.
@MainActor
final class AppContainer {
    let authService: any AuthService
    /// Sand når vi kører uden Supabase (ingen Secrets.plist).
    let usesMockServices: Bool

    init(authService: any AuthService, usesMockServices: Bool) {
        self.authService = authService
        self.usesMockServices = usesMockServices
    }

    /// Rigtige services, hvis Secrets.plist findes – ellers mocks.
    static func live() -> AppContainer {
        guard let config = SupabaseConfig.load() else {
            return mock()
        }
        let client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
        return AppContainer(
            authService: SupabaseAuthService(client: client),
            usesMockServices: false
        )
    }

    /// Kun falske services – til Simulator, previews og tests.
    static func mock(signedIn: Bool = false) -> AppContainer {
        AppContainer(
            authService: MockAuthService(storedSession: signedIn ? MockAuthService.sampleSession : nil),
            usesMockServices: true
        )
    }
}
