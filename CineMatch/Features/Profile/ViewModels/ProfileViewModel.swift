//
//  ProfileViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// "Profile": brugerens tal (bedømte film, favoritter, streak), streamingtjenester, "Start fresh" og "Sign out".
///
/// "Start fresh" sletter alle brugerens domme (Swipe, Search og "Seen it") og dagens pick/streak,
/// så modellen starter forfra. Streamingtjenesterne bevares – dem ændrer man for sig.
/// Målinger (`recommendation_*`) slettes ikke: appen må ikke (RLS), og de er anonyme statistik for modellen.
@Observable
@MainActor
final class ProfileViewModel {
    /// Alle sete film (Horrible til Fantastic).
    private(set) var ratedCount = 0
    /// Great + Fantastic.
    private(set) var lovedCount = 0
    /// Dage i træk med en dom over dagens pick.
    private(set) var streak = 0
    /// True mens "Start fresh" sletter.
    private(set) var isResetting = false
    var errorMessage: String?

    let email: String?
    /// Alle bunker med brugerens domme. Den første er den, tallene vises fra (Swipe/Search/Today).
    private let signalServices: [any TasteSignalService]
    private let dailyPicks: DailyPickStore
    var now: () -> Date = { .now }

    init(email: String?, signalServices: [any TasteSignalService], dailyPicks: DailyPickStore) {
        self.email = email
        self.signalServices = signalServices
        self.dailyPicks = dailyPicks
    }

    /// Stort bogstav i avataren, fx "P" for peter@…
    var initial: String {
        email?.first.map { String($0).uppercased() } ?? "?"
    }

    var hasRatings: Bool { ratedCount > 0 }

    /// Henter tallene. Kaldes, når fanen vises.
    func load() async {
        streak = dailyPicks.streak(on: now())
        guard let signals = try? await signalServices.first?.allSignals() else { return }
        let verdicts = Dictionary(signals.map { ($0.movieID, $0.verdict) }, uniquingKeysWith: { newest, _ in newest })
        ratedCount = verdicts.values.filter(\.isSeen).count
        lovedCount = verdicts.values.filter(\.isPositive).count
    }

    /// Sletter alle domme og dagens pick. Returnerer `true`, når alt er slettet.
    /// Går noget galt undervejs, vises en fejl, og tallene viser det, der faktisk er tilbage.
    func startFresh() async -> Bool {
        guard !isResetting else { return false }
        isResetting = true
        errorMessage = nil
        defer { isResetting = false }
        do {
            for service in signalServices {
                try await service.deleteAllSignals()
            }
            dailyPicks.reset()
            AppLog.shared.info("Profile: started fresh")
            await load()
            return true
        } catch {
            AppLog.shared.error("Profile: start fresh failed", error)
            errorMessage = "Couldn't delete your ratings. Please try again."
            await load()
            return false
        }
    }
}
