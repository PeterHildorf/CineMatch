//
//  SupabaseTasteSignalService.swift
//  CineMatch
//

import Foundation
import Supabase

/// Gemmer brugerens svar i Supabase-tabellen `taste_signals`, så de følger brugeren og ikke telefonen.
/// Én instans pr. pipeline: swipe, søgning og stjerner har hver deres svar (se migration 0004).
/// Dommen gemmes som tal i `rating` (0/1/2/3/5, se migration 0005) og groft i `signal` (like/dislike/unseen).
final class SupabaseTasteSignalService: TasteSignalService {
    private let client: SupabaseClient
    private let pipeline: PipelineID

    init(client: SupabaseClient, pipeline: PipelineID) {
        self.client = client
        self.pipeline = pipeline
    }

    func allSignals() async throws -> [TasteSignal] {
        do {
            let userID = try await currentUserID()
            let rows: [Row] = try await client.from(Row.table)
                .select("movie_id, signal, rating, source")
                .eq("user_id", value: userID)
                .eq("pipeline", value: pipeline.rawValue)
                .order("updated_at", ascending: false)   // nyeste først
                .execute()
                .value
            return rows.compactMap(Self.signal(from:))
        } catch {
            throw mapError(error, "allSignals")
        }
    }

    func save(_ signal: TasteSignal) async throws {
        do {
            let userID = try await currentUserID()
            let row = Row(
                userID: userID,
                pipeline: pipeline.rawValue,
                movieID: signal.movieID,
                signal: signal.kind.rawValue,
                rating: Double(signal.score),   // skalaens tal: 0, 1, 2, 3 eller 5
                source: signal.source.rawValue
            )
            try await client.from(Row.table)
                .upsert(row, onConflict: "user_id,pipeline,movie_id")
                .execute()
        } catch {
            throw mapError(error, "save movie \(signal.movieID)")
        }
    }

    func deleteSignal(movieID: Int) async throws {
        do {
            let userID = try await currentUserID()
            try await client.from(Row.table)
                .delete()
                .eq("user_id", value: userID)
                .eq("pipeline", value: pipeline.rawValue)
                .eq("movie_id", value: movieID)
                .execute()
        } catch {
            throw mapError(error, "delete movie \(movieID)")
        }
    }

    func deleteAllSignals() async throws {
        do {
            let userID = try await currentUserID()
            try await client.from(Row.table)
                .delete()
                .eq("user_id", value: userID)
                .eq("pipeline", value: pipeline.rawValue)
                .execute()
        } catch {
            throw mapError(error, "delete all")
        }
    }

    // MARK: - Hjælpere

    private func currentUserID() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch is URLError {
            // Offline: brug den gemte session, hvis der er en.
            guard let session = client.auth.currentSession else { throw TasteSignalServiceError.network }
            return session.user.id
        } catch {
            AppLog.shared.error("No valid Supabase session", error)
            throw TasteSignalServiceError.unauthorized
        }
    }

    /// `nil`, hvis rækken har en værdi, appen ikke kender.
    /// `rating` er skalaens tal. Gamle rækker uden tal (swipe før 0005) oversættes: like → Great, dislike → Bad.
    static func signal(from row: Row) -> TasteSignal? {
        let verdict: Verdict?
        if let rating = row.rating {
            verdict = Verdict(storedScore: rating)
        } else {
            switch TasteSignal.Kind(rawValue: row.signal) {
            case .like: verdict = .great
            case .dislike: verdict = .bad
            case .unseen: verdict = .notSeen
            case nil: verdict = nil
            }
        }
        guard let verdict else { return nil }
        return TasteSignal(movieID: row.movieID, verdict: verdict, source: TasteSignal.Source(rawValue: row.source) ?? .onboarding)
    }

    /// Logger den rå fejl (brugeren ser kun en generel besked) og oversætter den.
    private func mapError(_ error: Error, _ operation: String) -> TasteSignalServiceError {
        AppLog.shared.error("taste_signals [\(pipeline.rawValue)] \(operation) failed", error)
        if let error = error as? TasteSignalServiceError { return error }
        if error is URLError { return .network }
        return .unknown
    }

    /// Én række i `taste_signals`. Ved læsning mangler `user_id` og `pipeline` (de vælges ikke).
    nonisolated struct Row: Codable, Sendable {
        static let table = "taste_signals"

        var userID: UUID?
        var pipeline: String?
        let movieID: Int
        let signal: String
        let rating: Double?
        let source: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", pipeline, movieID = "movie_id", signal, rating, source
        }

        // `rating` skrives altid (også som null), så en upsert kan fjerne gamle stjerner.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(userID, forKey: .userID)
            try container.encodeIfPresent(pipeline, forKey: .pipeline)
            try container.encode(movieID, forKey: .movieID)
            try container.encode(signal, forKey: .signal)
            try container.encode(rating, forKey: .rating)
            try container.encode(source, forKey: .source)
        }
    }
}
