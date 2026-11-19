import Foundation
import Testing
@testable import CineMatch

@MainActor
struct DailyPickMigrationTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "UTC")!
        return result
    }
    private let monday = Date(timeIntervalSince1970: 1_800_000_000)
    private var tuesday: Date { monday.addingTimeInterval(24 * 3600) }

    @Test func movesOnlyProgressAndLeavesLegacyMovieReferencesUntouched() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let old = DailyPickStore(defaults: defaults, key: "old", calendar: calendar)
        _ = old.pick(from: [700], on: monday)
        old.markAnswered(movieID: 700, on: monday)
        old.pass(movieID: 800, on: monday)
        let oldData = try #require(defaults.data(forKey: "old"))

        let migrated = DailyPickStore(defaults: defaults, key: "new", calendar: calendar, legacyKey: "old")

        #expect(migrated.streak(on: tuesday) == 1)
        #expect(migrated.pick(from: [800, 700, 900], on: tuesday) == 800,
                "A legacy passed ID must not exclude an unrelated TMDB film")
        #expect(defaults.data(forKey: "old") == oldData)
        let reloaded = DailyPickStore(defaults: defaults, key: "new", calendar: calendar, legacyKey: "old")
        #expect(reloaded.streak(on: tuesday) == 1)
        #expect(reloaded.pick(from: [900, 800], on: tuesday) == 800)
    }

    @Test func explicitResetCannotReimportAnOldStreak() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let old = DailyPickStore(defaults: defaults, key: "old", calendar: calendar)
        _ = old.pick(from: [700], on: monday)
        old.markAnswered(movieID: 700, on: monday)
        let migrated = DailyPickStore(defaults: defaults, key: "new", calendar: calendar, legacyKey: "old")
        #expect(migrated.streak(on: monday) == 1)

        migrated.reset()
        let reloaded = DailyPickStore(defaults: defaults, key: "new", calendar: calendar, legacyKey: "old")

        #expect(reloaded.streak(on: monday) == 0)
        #expect(!reloaded.isDone(on: monday))
        #expect(old.streak(on: monday) == 1, "Original data stays available")
    }

    @Test func existingDestinationHistoryIsNotOverwritten() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let old = DailyPickStore(defaults: defaults, key: "old", calendar: calendar)
        _ = old.pick(from: [700], on: monday)
        old.markAnswered(movieID: 700, on: monday)
        let current = DailyPickStore(defaults: defaults, key: "new", calendar: calendar)
        _ = current.pick(from: [10], on: tuesday)

        let reloaded = DailyPickStore(defaults: defaults, key: "new", calendar: calendar, legacyKey: "old")

        #expect(!reloaded.isDone(on: monday))
        #expect(reloaded.pick(from: [20, 10], on: tuesday) == 10)
    }
}
