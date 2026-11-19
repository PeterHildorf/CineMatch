//
//  RatingModelStore.swift
//  CineMatch
//

import Foundation

/// Indlæser `cinematch_rating_model.json` (Antons nye model) én gang og deler den mellem services.
actor RatingModelStore {
    nonisolated static let fileName = "cinematch_rating_model"

    private let bundle: Bundle
    private var cached: RatingRecommender?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Til tests og previews: en model, der allerede er indlæst.
    init(preloaded recommender: RatingRecommender) {
        bundle = .main
        cached = recommender
    }

    nonisolated static func isAvailable(in bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: fileName, withExtension: "json") != nil
    }

    func recommender() throws -> RatingRecommender {
        if let cached { return cached }
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "json") else {
            AppLog.shared.error("cinematch_rating_model.json not found in app bundle")
            throw ModelStoreError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let recommender = try RatingRecommender(file: JSONDecoder().decode(RatingModelFile.self, from: data))
            cached = recommender
            return recommender
        } catch {
            AppLog.shared.error("Couldn't load cinematch_rating_model.json", error)
            throw ModelStoreError.invalidData
        }
    }
}
