//
//  MFModelStore.swift
//  CineMatch
//

import Foundation

/// Indlæser `cinematch_mf.json` (Mikkels model) én gang og deler den mellem services.
actor MFModelStore {
    nonisolated static let fileName = "cinematch_mf"

    private let bundle: Bundle
    private var cached: MatrixFactorizationRecommender?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Til tests og previews: en model, der allerede er indlæst.
    init(preloaded recommender: MatrixFactorizationRecommender) {
        bundle = .main
        cached = recommender
    }

    /// Ligger Mikkels modelfil i appen? Så bruger appen den i stedet for Antons.
    nonisolated static func isAvailable(in bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: fileName, withExtension: "json") != nil
    }

    func recommender() throws -> MatrixFactorizationRecommender {
        if let cached { return cached }
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "json") else {
            throw ModelStoreError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let recommender = try MatrixFactorizationRecommender(file: JSONDecoder().decode(MFModelFile.self, from: data))
            cached = recommender
            return recommender
        } catch {
            throw ModelStoreError.invalidData
        }
    }
}
