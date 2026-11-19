import Foundation

/// Loads and validates one verified export, off the main actor. Failures never select another model.
actor ConditionalNeighborModelStore {
    nonisolated static let fileName = "cinematch_knn"
    private let bundle: Bundle
    private var cached: ConditionalNeighborRecommender?

    init(bundle: Bundle = .main) { self.bundle = bundle }

    init(preloaded recommender: ConditionalNeighborRecommender) {
        bundle = .main
        cached = recommender
    }

    nonisolated static func isAvailable(in bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: fileName, withExtension: "json") != nil
    }

    func recommender() throws -> ConditionalNeighborRecommender {
        if let cached { return cached }
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "json") else {
            AppLog.shared.error("cinematch_knn.json not found in app bundle")
            throw ModelStoreError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let recommender = try ConditionalNeighborRecommender(
                file: JSONDecoder().decode(ConditionalNeighborModelFile.self, from: data)
            )
            cached = recommender
            return recommender
        } catch {
            AppLog.shared.error("Couldn't load verified cinematch_knn.json", error)
            throw ModelStoreError.invalidData
        }
    }
}
