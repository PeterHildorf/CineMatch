//
//  SupabaseRecommendationEventLogger.swift
//  CineMatch
//

import Foundation
import Supabase

/// Skriver batches, visninger og "Seen it" til Supabase, så præcisionen kan måles (migration 0004).
///
/// - Events sendes ét ad gangen i den rækkefølge, de blev logget: et batch skal findes, før dets
///   visninger og feedback kan indsættes (fremmednøgle).
/// - Fejl ignoreres. Er brugeren offline, går de events tabt – det koster lidt data, aldrig en fejl i appen.
/// - Bruger-id fastholdes, når eventet køes. Et kontoskift må aldrig flytte målinger til den næste bruger.
final class SupabaseRecommendationEventLogger: RecommendationEventLogger {
    private let client: SupabaseClient?
    private let pipeline: PipelineID
    private let currentUserID: () -> UUID?
    private let sendOverride: ((RecommendationEvent, UUID) async throws -> Void)?
    /// Det seneste event i køen. Næste event venter på det.
    private var tail: Task<Void, Never>?

    init(client: SupabaseClient, pipeline: PipelineID) {
        self.client = client
        self.pipeline = pipeline
        currentUserID = { client.auth.currentSession?.user.id }
        sendOverride = nil
    }

    /// Exercises queue/session behaviour without sending network requests.
    init(
        pipeline: PipelineID,
        currentUserID: @escaping () -> UUID?,
        send: @escaping (RecommendationEvent, UUID) async throws -> Void
    ) {
        client = nil
        self.pipeline = pipeline
        self.currentUserID = currentUserID
        sendOverride = send
    }

    func log(_ event: RecommendationEvent) {
        guard let userID = currentUserID() else { return }
        let previous = tail
        tail = Task {
            await previous?.value
            guard currentUserID() == userID else { return }
            do {
                try await send(event, userID: userID)
            } catch {
                AppLog.shared.error("Couldn't send \(event) [\(pipeline.rawValue)]", error)
            }
        }
    }

    /// Waits for the existing queue, making session-switch tests deterministic.
    func waitForPendingEvents() async { await tail?.value }

    private func send(_ event: RecommendationEvent, userID: UUID) async throws {
        if let sendOverride {
            try await sendOverride(event, userID)
            return
        }
        guard let client else { return }
        // Every write also includes the captured user ID. If authentication
        // changes during the request, RLS rejects it rather than attributing it
        // to the new session through the database's auth.uid() default.
        switch event {
        case .batch(let batch):
            try await client.from("recommendation_batches")
                .upsert(
                    BatchRow(id: batch.id, pipeline: pipeline.rawValue, modelVersion: batch.modelVersion,
                             inputCount: batch.inputCount, createdAt: batch.createdAt, userID: userID),
                    onConflict: "id", ignoreDuplicates: true
                )
                .execute()
        case let .impressions(batchID, impressions):
            let rows = impressions.map {
                ImpressionRow(batchID: batchID, movieID: $0.movieID, rank: $0.rank, score: $0.score,
                              shownPosition: $0.shownPosition, userID: userID)
            }
            try await client.from("recommendation_impressions")
                .upsert(rows, onConflict: "batch_id,movie_id", ignoreDuplicates: true)   // første visning tæller
                .execute()
        case let .feedback(batchID, movieID, verdict):
            try await client.from("recommendation_feedback")
                .upsert(FeedbackRow(batchID: batchID, movieID: movieID, verdict: verdict, userID: userID),
                        onConflict: "batch_id,movie_id", ignoreDuplicates: true)
                .execute()
        }
    }

    // MARK: - Rækker

    nonisolated struct BatchRow: Encodable, Sendable {
        let id: UUID
        let pipeline: String
        let modelVersion: String
        let inputCount: Int
        let createdAt: Date
        var userID: UUID? = nil

        enum CodingKeys: String, CodingKey {
            case id, pipeline, modelVersion = "model_version", inputCount = "input_count", createdAt = "created_at"
            case userID = "user_id"
        }
    }

    nonisolated struct ImpressionRow: Encodable, Sendable {
        let batchID: UUID
        let movieID: Int
        let rank: Int
        let score: Double?
        let shownPosition: Int
        var userID: UUID? = nil

        enum CodingKeys: String, CodingKey {
            case batchID = "batch_id", movieID = "movie_id", rank, score, shownPosition = "shown_position"
            case userID = "user_id"
        }

        // Alle rækker i én upsert skal have de samme nøgler, så `score` skrives også som null.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(batchID, forKey: .batchID)
            try container.encode(movieID, forKey: .movieID)
            try container.encode(rank, forKey: .rank)
            try container.encode(score, forKey: .score)
            try container.encode(shownPosition, forKey: .shownPosition)
            try container.encodeIfPresent(userID, forKey: .userID)
        }
    }

    /// `outcome` (liked/disliked) til målingerne fra 0004, `score` (1–5) fra 0005/0006.
    nonisolated struct FeedbackRow: Encodable, Sendable {
        let batchID: UUID
        let movieID: Int
        let outcome: String
        let score: Int
        let userID: UUID?

        init(batchID: UUID, movieID: Int, verdict: Verdict, userID: UUID? = nil) {
            self.batchID = batchID
            self.movieID = movieID
            self.userID = userID
            outcome = RecommendationOutcome(verdict).rawValue
            score = verdict.score
        }

        enum CodingKeys: String, CodingKey {
            case batchID = "batch_id", movieID = "movie_id", outcome, score
            case userID = "user_id"
        }
    }
}
