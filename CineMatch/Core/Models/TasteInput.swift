//
//  TasteInput.swift
//  CineMatch
//

/// Hvad den aktive model lærer af. Bestemmer vejledningsteksten og hvornår der er nok svar.
///
/// Begge modeller får samme skala (`Verdict`). Forskellen er, hvad de kan bruge i dag:
/// - Antons model tager kun en liste af likes, så kun Great og Fantastic tæller.
/// - Mikkels model tager alle sete film med deres tal (1–5).
enum TasteInput: Equatable, Sendable {
    /// Antons model: Great/Fantastic.
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
