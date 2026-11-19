//
//  TasteInput.swift
//  CineMatch
//

/// Hvad den aktive model lærer af. Bestemmer vejledningsteksten og hvornår der er nok svar.
///
/// All models receive the same verdict scale. The active conditional model requires five
/// supported Great/Fantastic answers for onboarding and excludes every seen film.
enum TasteInput: Equatable, Sendable {
    /// Five positive opinions, used by the active conditional model's onboarding policy.
    case likes
    /// Mikkels model: alle sete film.
    case starRatings

    /// Så mange svar skal der til, før modellen kender brugerens smag.
    static let minimumCount = 5

    /// Fx "Rate at least 5 movies Great or Fantastic".
    var requirementText: String {
        switch self {
        case .likes: "Rate at least \(Self.minimumCount) movies Great or Fantastic"
        case .starRatings: "Rate at least \(Self.minimumCount) movies you've seen"
        }
    }
}
