//
//  AppLog.swift
//  CineMatch
//

import Foundation
import os
import Synchronization

/// Appens log. Skriver til Xcode-konsollen (os.Logger) og gemmer de seneste linjer i hukommelsen,
/// så de kan ses og deles fra fejlskærmene ("Show log").
///
/// - Log den RÅ fejl der, hvor den opstår (fx i en service), før den oversættes til en generel fejl.
/// - Log aldrig adgangskoder, tokens eller e-mails.
/// - `nonisolated` og trådsikker, så den kan bruges fra actors (fx `ModelStore`) og baggrundsopgaver.
nonisolated final class AppLog: Sendable {
    static let shared = AppLog()

    nonisolated struct Entry: Sendable {
        enum Level: String, Sendable {
            case info = "INFO"
            case error = "ERROR"
        }

        let date: Date
        let level: Level
        /// Filen, der loggede, fx "SupabaseTasteSignalService".
        let source: String
        let message: String
    }

    /// Så mange linjer gemmes. De ældste forsvinder først.
    private let capacity: Int
    private let entries = Mutex<[Entry]>([])
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CineMatch", category: "app")

    init(capacity: Int = 500) {
        self.capacity = capacity
    }

    func info(_ message: String, fileID: String = #fileID) {
        append(.info, message, fileID: fileID)
    }

    /// Logger en fejl med alle detaljer (`String(reflecting:)` viser fx Supabase' fejlkode og besked).
    func error(_ message: String, _ error: (any Error)? = nil, fileID: String = #fileID) {
        let text = error.map { "\(message): \(String(reflecting: $0))" } ?? message
        append(.error, text, fileID: fileID)
    }

    /// Kopi af loggen, ældste først.
    var allEntries: [Entry] {
        entries.withLock { $0 }
    }

    func clear() {
        entries.withLock { $0.removeAll() }
    }

    /// Hele loggen som tekst med app- og enhedsinfo øverst. Det er det, "Show log" viser og deler.
    func report(now: Date = .now) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let header = [
            "CineMatch \(version) (\(build))",
            ProcessInfo.processInfo.operatingSystemVersionString,
            "Log created \(Self.format(now))",
            "",
        ]
        let lines = allEntries.map { "\(Self.format($0.date)) [\($0.level.rawValue)] \($0.source): \($0.message)" }
        return (header + (lines.isEmpty ? ["(empty)"] : lines)).joined(separator: "\n")
    }

    // MARK: - Hjælpere

    private func append(_ level: Entry.Level, _ message: String, fileID: String) {
        let entry = Entry(date: .now, level: level, source: Self.source(from: fileID), message: message)
        entries.withLock { entries in
            entries.append(entry)
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        }
        switch level {
        case .info: logger.info("\(entry.source, privacy: .public): \(message, privacy: .public)")
        case .error: logger.error("\(entry.source, privacy: .public): \(message, privacy: .public)")
        }
    }

    /// "CineMatch/SupabaseTasteSignalService.swift" → "SupabaseTasteSignalService".
    static func source(from fileID: String) -> String {
        let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        return file.hasSuffix(".swift") ? String(file.dropLast(6)) : file
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
}
