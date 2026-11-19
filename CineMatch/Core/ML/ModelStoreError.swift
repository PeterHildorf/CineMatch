/// Shared load failures for local model stores.
nonisolated enum ModelStoreError: Error, Equatable {
    case fileNotFound
    case invalidData
}
