//
//  StreamingServicesViewModel.swift
//  CineMatch
//

import Observation

/// "Which services do you have?": brugeren vælger sine streamingtjenester.
/// Vises første gang efter login og kan åbnes igen fra kontomenuen.
@Observable
@MainActor
final class StreamingServicesViewModel {
    private(set) var selected: Set<StreamingService> = []
    private(set) var isSaving = false
    var errorMessage: String?

    /// Resten af indstillingerne (fx "Only my services") bevares, når tjenesterne gemmes.
    private var preferences = StreamingPreferences()
    private let preferencesService: any PreferencesService

    init(preferencesService: any PreferencesService) {
        self.preferencesService = preferencesService
    }

    var services: [StreamingService] { StreamingService.allCases }
    var selectedCountText: String {
        "\(selected.count) selected · you can change this later in the account menu"
    }

    /// True, hvis brugeren aldrig har valgt tjenester. Så skal valget vises.
    func needsSetup() async -> Bool {
        (try? await preferencesService.streamingPreferences()) == nil
    }

    func load() async {
        preferences = (try? await preferencesService.streamingPreferences()) ?? StreamingPreferences()
        selected = preferences.services
        errorMessage = nil
    }

    func isSelected(_ service: StreamingService) -> Bool {
        selected.contains(service)
    }

    func toggle(_ service: StreamingService) {
        if selected.contains(service) {
            selected.remove(service)
        } else {
            selected.insert(service)
        }
    }

    /// Gemmer valget. Returnerer `true`, når skærmen må lukkes.
    /// Ingen tjenester er et gyldigt valg ("I don't have any").
    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        var updated = preferences
        updated.services = selected
        if selected.isEmpty { updated.onlyMyServices = false }
        do {
            try await preferencesService.saveStreamingPreferences(updated)
            preferences = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't save your services. Please try again."
            return false
        }
    }
}
