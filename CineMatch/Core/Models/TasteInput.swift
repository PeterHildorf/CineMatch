//
//  TasteInput.swift
//  CineMatch
//

/// Hvad den aktive model lærer af. Bestemmer onboardingens tekst og hvornår der er nok svar.
enum TasteInput: Equatable, Sendable {
    /// Antons model: likes.
    case likes
    /// Mikkels model: stjerner (½–5). Likes uden stjerner bruges ikke af modellen.
    case starRatings

    /// Så mange svar skal der til, før modellen kender brugerens smag.
    static let minimumCount = 5

    /// Fx "Like at least 5 movies in Swipe".
    var requirementText: String {
        switch self {
        case .likes: "Like at least \(Self.minimumCount) movies in Swipe"
        case .starRatings: "Rate at least \(Self.minimumCount) movies with stars in Rate"
        }
    }
}
