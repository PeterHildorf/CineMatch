//
//  DailyPickStore.swift
//  CineMatch
//

import Foundation

/// Husker "Tonight's pick": den samme film hele dagen, en ny i morgen, og hvor mange dage i træk
/// brugeren har givet en pick en dom (streak). Gemmes lokalt på telefonen.
///
/// Reglerne:
/// - Dagens pick er den bedste kandidat, der ikke har været dagens pick før, og som brugeren ikke har sprunget over.
/// - Har brugeren allerede set den ("Seen it"), tæller dagen med i streaken, og den næste kandidat bliver dagens pick.
///   Pointen er, at brugeren altid har en film at se i aften.
/// - "Another pick" springer filmen over (den bliver aldrig dagens pick igen) og vælger den næste.
/// - Forsvinder dagens pick fra kandidaterne (fx bedømt i Swipe), vælges en ny.
final class DailyPickStore {
    private struct Stored: Codable {
        /// Dag ("2026-11-18") → dagens film.
        var featured: [String: Int] = [:]
        /// Dage, hvor dagens pick fik en dom.
        var answeredDays: Set<String> = []
        /// Film, brugeren har sprunget over med "Another pick".
        var passed: Set<Int> = []
    }

    private let defaults: UserDefaults
    private let key: String
    private let calendar: Calendar
    private var stored: Stored

    /// `key` skal være forskellig pr. pipeline (og pr. bruger, hvis flere logger ind på samme telefon).
    init(defaults: UserDefaults = .standard, key: String, calendar: Calendar = .current) {
        self.defaults = defaults
        self.key = key
        self.calendar = calendar
        stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    /// Dagens pick blandt `candidates` (bedste først). `nil`, hvis der ingen kandidater er.
    func pick(from candidates: [Int], on date: Date) -> Int? {
        let day = dayKey(date)
        guard !candidates.isEmpty else { return nil }
        if let today = stored.featured[day], candidates.contains(today) {
            return today
        }
        let used = Set(stored.featured.filter { $0.key != day }.values).union(stored.passed)
        // Har brugeren været igennem alle kandidater, starter vi forfra fra toppen.
        let choice = candidates.first { !used.contains($0) }
            ?? candidates.first { !stored.passed.contains($0) }
            ?? candidates[0]
        stored.featured[day] = choice
        save()
        return choice
    }

    /// Kaldes ved "Seen it". Er filmen dagens pick, tæller dagen med i streaken.
    /// Filmen er bedømt og forsvinder fra kandidaterne, så næste `pick` vælger en ny.
    func markAnswered(movieID: Int, on date: Date) {
        let day = dayKey(date)
        guard stored.featured[day] == movieID else { return }
        stored.answeredDays.insert(day)
        save()
    }

    /// "Another pick": filmen bliver aldrig dagens pick igen.
    func pass(movieID: Int, on date: Date) {
        stored.passed.insert(movieID)
        if stored.featured[dayKey(date)] == movieID {
            stored.featured[dayKey(date)] = nil
        }
        save()
    }

    /// True, hvis brugeren har givet en pick en dom i dag.
    func isDone(on date: Date) -> Bool {
        stored.answeredDays.contains(dayKey(date))
    }

    /// Dage i træk med en dom over en pick. I dag tæller med, hvis den er klaret; ellers tælles fra i går,
    /// så streaken ikke "knækker", før dagen er omme.
    func streak(on date: Date) -> Int {
        var day = isDone(on: date) ? date : calendar.date(byAdding: .day, value: -1, to: date) ?? date
        var count = 0
        while stored.answeredDays.contains(dayKey(day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: - Hjælpere

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
