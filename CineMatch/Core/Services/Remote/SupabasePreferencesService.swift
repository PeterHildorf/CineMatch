//
//  SupabasePreferencesService.swift
//  CineMatch
//

import Foundation
import Supabase

/// Gemmer brugerens streamingtjenester i Supabase-tabellen `preferences` (se migration 0003),
/// så valget følger brugeren og ikke telefonen.
/// Ingen række, eller `streaming_services` er null = brugeren har aldrig valgt tjenester.
final class SupabasePreferencesService: PreferencesService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func streamingPreferences() async throws -> StreamingPreferences? {
        do {
            let userID = try await currentUserID()
            let rows: [Row] = try await client.from(Row.table)
                .select("streaming_services, only_my_services")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first, let services = row.streamingServices else { return nil }
            // Ukendte tjenester (fx fra en nyere app-version) springes over.
            return StreamingPreferences(
                services: Set(services.compactMap(StreamingService.init(rawValue:))),
                onlyMyServices: row.onlyMyServices ?? false
            )
        } catch {
            AppLog.shared.error("preferences: load failed", error)
            throw error
        }
    }

    func saveStreamingPreferences(_ preferences: StreamingPreferences) async throws {
        do {
            let row = Row(
                userID: try await currentUserID(),
                streamingServices: preferences.services.map(\.rawValue).sorted(),
                onlyMyServices: preferences.onlyMyServices,
                updatedAt: Date()
            )
            try await client.from(Row.table)
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            AppLog.shared.error("preferences: save failed", error)
            throw error
        }
    }

    func deleteStreamingPreferences() async throws {
        do {
            let userID = try await currentUserID()
            // Kun tjenesterne nulstilles – resten af rækken (fx favoritgenrer) bevares.
            try await client.from(Row.table)
                .update(Row(streamingServices: nil, onlyMyServices: false, updatedAt: Date()))
                .eq("user_id", value: userID)
                .execute()
        } catch {
            AppLog.shared.error("preferences: delete failed", error)
            throw error
        }
    }

    private func currentUserID() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch is URLError {
            // Offline: brug den gemte session, hvis der er en.
            guard let session = client.auth.currentSession else { throw TasteSignalServiceError.network }
            return session.user.id
        } catch {
            throw TasteSignalServiceError.unauthorized
        }
    }

    /// Én række i `preferences`. Ved læsning mangler `user_id` og `updated_at` (de vælges ikke).
    nonisolated struct Row: Codable, Sendable {
        static let table = "preferences"

        var userID: UUID?
        let streamingServices: [String]?
        let onlyMyServices: Bool?
        var updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", streamingServices = "streaming_services"
            case onlyMyServices = "only_my_services", updatedAt = "updated_at"
        }

        // `streaming_services` skrives altid (også som null), så en nulstilling virker.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(userID, forKey: .userID)
            try container.encode(streamingServices, forKey: .streamingServices)
            try container.encodeIfPresent(onlyMyServices, forKey: .onlyMyServices)
            try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        }
    }
}
