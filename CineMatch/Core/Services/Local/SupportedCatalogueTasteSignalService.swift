import Foundation

/// Exposes only verified, model-supported TMDB opinions to the active app.
///
/// The canonical store uses TMDB IDs. Legacy stores retain their Letterboxd IDs;
/// reads translate only the verified mappings shipped with the model. Reading
/// never copies, updates or deletes source records, including unsupported ones.
final class SupportedCatalogueTasteSignalService: TasteSignalService {
    private let store: ConditionalNeighborModelStore
    private let canonical: any TasteSignalService
    private let legacy: [any TasteSignalService]

    init(
        store: ConditionalNeighborModelStore,
        canonical: any TasteSignalService,
        legacy: [any TasteSignalService] = []
    ) {
        self.store = store
        self.canonical = canonical
        self.legacy = legacy
    }

    func allSignals() async throws -> [TasteSignal] {
        let model = try await store.recommender()
        let supported = model.supportedTMDBIDs
        var newest: [Int: TasteSignal] = [:]

        // Canonical records win equal/unknown timestamps. Within each source,
        // retain its first record on a tie; stores return newest records first.
        for signal in try await canonical.allSignals()
        where supported.contains(signal.movieID) {
            Self.keepNewest(signal, in: &newest)
        }
        for source in legacy {
            for signal in try await source.allSignals() {
                guard let tmdbID = model.legacyTMDBID(letterboxdId: signal.movieID),
                      supported.contains(tmdbID) else { continue }
                Self.keepNewest(
                    TasteSignal(
                        movieID: tmdbID,
                        verdict: signal.verdict,
                        source: signal.source,
                        answeredAt: signal.answeredAt
                    ),
                    in: &newest
                )
            }
        }
        return newest.values.sorted {
            let left = $0.answeredAt ?? .distantPast
            let right = $1.answeredAt ?? .distantPast
            return left == right ? $0.movieID < $1.movieID : left > right
        }
    }

    func save(_ signal: TasteSignal) async throws {
        let model = try await store.recommender()
        guard model.supportedTMDBIDs.contains(signal.movieID) else {
            throw TasteSignalServiceError.unknown
        }
        // Remote storage supplies its own server timestamp. Local storage also
        // needs a timestamp so a new answer supersedes older translated records.
        var dated = signal
        if dated.answeredAt == nil { dated.answeredAt = .now }
        try await canonical.save(dated)
    }

    func deleteSignal(movieID: Int) async throws {
        let model = try await store.recommender()
        guard model.supportedTMDBIDs.contains(movieID) else {
            throw TasteSignalServiceError.unknown
        }
        let legacyIDs = model.legacyMappings
            .filter { $0.value == movieID }
            .map(\.key)
            .sorted()
        // Deleting only the canonical row would reveal the old opinion again.
        // Keep that row until all legacy deletions succeed, so a failed request
        // does not remove the current answer before cleaning its predecessors.
        for source in legacy {
            for sourceID in legacyIDs {
                try await source.deleteSignal(movieID: sourceID)
            }
        }
        try await canonical.deleteSignal(movieID: movieID)
    }

    func deleteAllSignals() async throws {
        // Explicit "Start fresh" clears original records too. Ordinary reads and
        // writes preserve unsupported legacy opinions for future recovery.
        for source in legacy { try await source.deleteAllSignals() }
        try await canonical.deleteAllSignals()
    }

    private static func keepNewest(_ signal: TasteSignal, in values: inout [Int: TasteSignal]) {
        if let previous = values[signal.movieID],
           (previous.answeredAt ?? .distantPast) >= (signal.answeredAt ?? .distantPast) {
            return
        }
        values[signal.movieID] = signal
    }
}
