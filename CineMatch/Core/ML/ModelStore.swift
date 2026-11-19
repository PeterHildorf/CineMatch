//
//  ModelStore.swift
//  CineMatch
//

import Foundation

/// Indlæser `cinematch_model.json` én gang og deler den mellem services.
/// Et `actor`, så den store fil læses uden for main thread, og kun én gang.
actor ModelStore {
    nonisolated static let fileName = "cinematch_model"

    private let bundle: Bundle
    private var cached: OnDeviceRecommender?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Til tests og previews: en model, der allerede er indlæst.
    init(preloaded recommender: OnDeviceRecommender) {
        bundle = .main
        cached = recommender
    }

    /// Ligger modelfilen i appen? Hvis ikke, bruger appen mocks.
    nonisolated static func isAvailable(in bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: fileName, withExtension: "json") != nil
    }

    func recommender() throws -> OnDeviceRecommender {
        if let cached { return cached }
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "json") else {
            AppLog.shared.error("cinematch_model.json not found in app bundle")
            throw ModelStoreError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let recommender = try OnDeviceRecommender(file: JSONDecoder().decode(ModelFile.self, from: data))
            cached = recommender
            return recommender
        } catch {
            AppLog.shared.error("Couldn't load cinematch_model.json", error)
            throw ModelStoreError.invalidData
        }
    }
}
