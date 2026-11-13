//
//  StreamingPreferences.swift
//  CineMatch
//

/// Brugerens valg af streamingtjenester. Bruges kun af appens filter, ikke som modelinput.
struct StreamingPreferences: Codable, Equatable, Sendable {
    var services: Set<StreamingService> = []
    /// "Only my services" på For You.
    var onlyMyServices = false
}
