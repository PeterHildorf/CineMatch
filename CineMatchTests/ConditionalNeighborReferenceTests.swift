import CryptoKit
import Foundation
import Testing
@testable import CineMatch

private final class ConditionalReferenceBundleMarker {}

@MainActor
struct ConditionalNeighborReferenceTests {
    private struct Reference: Decodable {
        struct Case: Decodable {
            struct Rating: Decodable { let tmdbId: Int; let stars: Double }
            struct Expected: Decodable {
                struct Item: Decodable { let tmdbId: Int; let score: Double }
                let ratingsUsed: Int
                let personalized: Bool?
                let positiveRatingsUsed: Int?
                let results: [Item]
            }
            let name: String
            let ratings: [Rating]
            let excluding: [Int]
            let limit: Int
            let expected: Expected
        }
        let schemaVersion: Int
        let modelVersion: String
        let bundleSHA256: String
        let sourceModelSHA256: String
        let scoreTolerance: Double?
        let cases: [Case]
    }

    private var modelBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: MockAuthService.self)
        #endif
    }

    private var referenceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: ConditionalReferenceBundleMarker.self)
        #endif
    }

    @Test func bundledVerifiedModelMatchesPythonReferenceScoresAndOrder() throws {
        let modelURL = try #require(modelBundle.url(forResource: "cinematch_knn", withExtension: "json"))
        let referenceURL = try #require(referenceBundle.url(forResource: "knn_reference_cases", withExtension: "json"))
        let data = try Data(contentsOf: modelURL)
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: referenceURL))
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(checksum == reference.bundleSHA256)
        #expect(reference.schemaVersion == 1 && !reference.cases.isEmpty)
        let model = try ConditionalNeighborRecommender(file: JSONDecoder().decode(ConditionalNeighborModelFile.self, from: data))
        #expect(model.modelVersion == reference.modelVersion)
        #expect(model.sourceModelSHA256 == reference.sourceModelSHA256)
        for testCase in reference.cases {
            let output = try model.recommend(
                ratings: testCase.ratings.map { .init(tmdbId: $0.tmdbId, stars: $0.stars) },
                excluding: Set(testCase.excluding), limit: testCase.limit
            )
            #expect(output.ratingsUsed == testCase.expected.ratingsUsed, "\(testCase.name)")
            if let personalized = testCase.expected.personalized {
                #expect(output.personalized == personalized, "\(testCase.name)")
            }
            if let positiveCount = testCase.expected.positiveRatingsUsed {
                #expect(output.positiveRatingsUsed == positiveCount, "\(testCase.name)")
            }
            #expect(output.results.map(\.tmdbId) == testCase.expected.results.map(\.tmdbId), "\(testCase.name): ordered movie IDs")
            for (got, expected) in zip(output.results, testCase.expected.results) {
                #expect(abs(got.score - expected.score) <= (reference.scoreTolerance ?? 1e-10), "\(testCase.name): \(got.tmdbId) score")
            }
        }
    }
}
