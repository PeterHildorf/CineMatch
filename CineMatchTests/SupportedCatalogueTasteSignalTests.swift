import Foundation
import Testing
@testable import CineMatch

@MainActor
struct SupportedCatalogueTasteSignalTests {
    private func makeStore() throws -> ConditionalNeighborModelStore {
        let json = """
        {
          "format":"cinematch.conditional-neighbors","schemaVersion":1,
          "modelType":"positive_conditional_neighbors","modelVersion":"test",
          "sourceModelSHA256":"0000000000000000000000000000000000000000000000000000000000000000",
          "tmdbIdentityVerified":true,
          "movies":[
            {"movieLensId":1,"tmdbId":10,"eligible":true,"title":"One","year":2001,"genres":[],"trainingCount":30},
            {"movieLensId":2,"tmdbId":20,"eligible":true,"title":"Two","year":2002,"genres":[],"trainingCount":20},
            {"movieLensId":3,"tmdbId":30,"eligible":true,"title":"Three","year":2003,"genres":[],"trainingCount":10},
            {"movieLensId":4,"tmdbId":40,"eligible":false,"title":"Excluded","year":2004,"genres":[],"trainingCount":5}
          ],
          "neighborOffsets":[0,0,0,0,0],"neighborIndices":[],"neighborWeights":[],
          "scoring":{"aggregation":"positive","ratingCenter":3,"fallback":"training_rating_count","tieBreak":"original_catalogue_order"},
          "legacyMappings":[
            {"letterboxdId":101,"tmdbId":10},
            {"letterboxdId":103,"tmdbId":10},
            {"letterboxdId":102,"tmdbId":20},
            {"letterboxdId":20,"tmdbId":30}
          ]
        }
        """
        return try ConditionalNeighborModelStore(preloaded: ConditionalNeighborRecommender(
            file: JSONDecoder().decode(ConditionalNeighborModelFile.self, from: Data(json.utf8))
        ))
    }

    private func date(_ value: Double) -> Date { Date(timeIntervalSince1970: value) }

    @Test func translatesOnlyVerifiedIDsAndKeepsLatestOpinionWithoutChangingSources() async throws {
        let canonical = MockTasteSignalService(signals: [
            TasteSignal(movieID: 10, verdict: .great, answeredAt: date(100)),
            TasteSignal(movieID: 20, verdict: .bad, answeredAt: date(200)),
            TasteSignal(movieID: 999, verdict: .great, answeredAt: date(300))
        ])
        let legacy = MockTasteSignalService(signals: [
            TasteSignal(movieID: 101, verdict: .fantastic, source: .feedback, answeredAt: date(101)),
            TasteSignal(movieID: 102, verdict: .great, answeredAt: date(200)),
            TasteSignal(movieID: 20, verdict: .neutral, answeredAt: date(150)),
            TasteSignal(movieID: 103, verdict: .horrible, answeredAt: date(99)),
            TasteSignal(movieID: 30, verdict: .great, answeredAt: date(400))
        ])
        let beforeCanonical = canonical.signals
        let beforeLegacy = legacy.signals
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )

        let values = try await service.allSignals()

        #expect(values.map(\.movieID) == [20, 30, 10])
        #expect(values[0].verdict == .bad, "Canonical wins an equal timestamp")
        #expect(values[1].verdict == .neutral, "Legacy integer 20 maps to TMDB 30, never TMDB 20")
        #expect(values[2].verdict == .fantastic)
        #expect(values[2].source == .feedback)
        #expect(values[2].answeredAt == date(101))
        #expect(canonical.signals == beforeCanonical)
        #expect(legacy.signals == beforeLegacy)
        #expect(canonical.saveCallCount == 0)
        #expect(legacy.saveCallCount == 0)
        #expect(try await service.allSignals() == values, "Read-through migration is deterministic")
    }

    @Test func canonicalWinsWhenBothTimestampsAreUnknown() async throws {
        let canonical = MockTasteSignalService(signals: [TasteSignal(movieID: 10, verdict: .great)])
        let legacy = MockTasteSignalService(signals: [TasteSignal(movieID: 101, verdict: .bad)])
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )
        let values = try await service.allSignals()
        #expect(values.count == 1)
        #expect(values.first?.verdict == .great)
        #expect(values.first?.answeredAt == nil)
    }

    @Test func newAnswersUseCanonicalStorageAndSupersedeLegacyOpinions() async throws {
        let canonical = MockTasteSignalService()
        let legacy = MockTasteSignalService(signals: [
            TasteSignal(movieID: 101, verdict: .great, answeredAt: date(100))
        ])
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )
        try await service.save(TasteSignal(movieID: 10, verdict: .notSeen, source: .feedback))
        let values = try await service.allSignals()

        #expect(values.first?.verdict == .notSeen)
        #expect(values.first?.source == .feedback)
        #expect(values.first?.answeredAt != nil)
        #expect(canonical.signals.first?.movieID == 10)
        #expect(legacy.signals.first?.movieID == 101)
        #expect(legacy.saveCallCount == 0)
    }

    @Test func unsupportedSavesCannotReachTheDatabase() async throws {
        let canonical = MockTasteSignalService()
        let service = SupportedCatalogueTasteSignalService(store: try makeStore(), canonical: canonical)
        do {
            try await service.save(TasteSignal(movieID: 40, verdict: .great))
            Issue.record("Excluded film was accepted")
        } catch {
            #expect(error as? TasteSignalServiceError == .unknown)
        }
        #expect(canonical.saveCallCount == 0)
    }

    @Test func deletionRemovesTranslatedPredecessorsWithoutDeletingCollidingIDs() async throws {
        let canonical = MockTasteSignalService(signals: [TasteSignal(movieID: 20, verdict: .great)])
        let legacy = MockTasteSignalService(signals: [
            TasteSignal(movieID: 102, verdict: .bad),
            TasteSignal(movieID: 20, verdict: .fantastic),
            TasteSignal(movieID: 999, verdict: .great)
        ])
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )

        try await service.deleteSignal(movieID: 20)

        #expect(canonical.signals.isEmpty)
        #expect(legacy.signals.map(\.movieID) == [20, 999])
        #expect(try await service.allSignals().map(\.movieID) == [30])
    }

    @Test func deletionRemovesEveryAliasAcrossLegacySources() async throws {
        let canonical = MockTasteSignalService(signals: [TasteSignal(movieID: 10, verdict: .great)])
        let swipe = MockTasteSignalService(signals: [TasteSignal(movieID: 101, verdict: .bad)])
        let search = MockTasteSignalService(signals: [TasteSignal(movieID: 103, verdict: .fantastic)])
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [swipe, search]
        )
        try await service.deleteSignal(movieID: 10)
        #expect(try await service.allSignals().isEmpty)
        #expect(swipe.signals.isEmpty)
        #expect(search.signals.isEmpty)
    }

    @Test func failedLegacyDeletionPreservesTheCurrentCanonicalAnswer() async throws {
        let canonical = MockTasteSignalService(signals: [TasteSignal(movieID: 10, verdict: .great)])
        let legacy = MockTasteSignalService(errorToThrow: .network)
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )
        do {
            try await service.deleteSignal(movieID: 10)
            Issue.record("Deletion should have failed")
        } catch {
            #expect(error as? TasteSignalServiceError == .network)
        }
        #expect(canonical.signals.count == 1)
    }

    @Test func failedLegacyReadDoesNotPretendTheUserHasNoOpinions() async throws {
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: MockTasteSignalService(),
            legacy: [MockTasteSignalService(errorToThrow: .network)]
        )
        do {
            _ = try await service.allSignals()
            Issue.record("Read should have failed")
        } catch {
            #expect(error as? TasteSignalServiceError == .network)
        }
    }

    @Test func explicitStartFreshAlsoClearsUnsupportedOriginalRecords() async throws {
        let canonical = MockTasteSignalService(signals: [TasteSignal(movieID: 999, verdict: .great)])
        let legacy = MockTasteSignalService(signals: [TasteSignal(movieID: 888, verdict: .bad)])
        let service = SupportedCatalogueTasteSignalService(
            store: try makeStore(), canonical: canonical, legacy: [legacy]
        )
        try await service.deleteAllSignals()
        #expect(canonical.signals.isEmpty)
        #expect(legacy.signals.isEmpty)
    }
}
