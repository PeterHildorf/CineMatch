//
//  RecommendationReason.swift
//  CineMatch
//

/// Gør en kort begrundelse længere med det, den anbefalede film har til fælles med den film,
/// den kommer fra. Fx "Because you liked Inception · Director: Christopher Nolan · Themes: dream, heist".
///
/// Data kommer fra TMDB (`TitleMedia`) og filmkataloget (`Title`). Mangler data, vises bare grundteksten.
/// Bemærk: Mikkels model anbefaler ud fra, hvad lignende seere kunne lide. De fælles træk forklarer
/// sammenhængen for brugeren, men er ikke det, modellen regner på.
enum RecommendationReason {
    /// Højst så mange grupper ("Director", "Cast" …) efter grundteksten.
    static let maxGroups = 2
    /// Højst så mange navne/ord pr. gruppe.
    static let maxValues = 2

    struct Group: Equatable, Sendable {
        let label: String
        let values: [String]
    }

    /// Fælles træk, vigtigste først: instruktør, skuespillere, temaer. Genrer kun, hvis intet andet er fælles.
    static func sharedGroups(
        title: Title?, media: TitleMedia?,
        because becauseTitle: Title?, becauseMedia: TitleMedia?
    ) -> [Group] {
        var groups: [Group] = []
        if let media, let becauseMedia {
            let candidates = [
                Group(label: "Director", values: shared(media.directors, becauseMedia.directors)),
                Group(label: "Cast", values: shared(media.cast, becauseMedia.cast)),
                Group(label: "Themes", values: shared(media.keywords, becauseMedia.keywords)),
            ]
            groups = candidates.filter { !$0.values.isEmpty }
        }
        if groups.isEmpty, let title, let becauseTitle {
            let genres = shared(title.genres, becauseTitle.genres)
            if !genres.isEmpty { groups = [Group(label: "Genres", values: genres)] }
        }
        return groups.prefix(maxGroups).map { Group(label: $0.label, values: Array($0.values.prefix(maxValues))) }
    }

    /// Grundteksten + fælles træk, adskilt af " · ".
    static func text(base: String, groups: [Group]) -> String {
        ([base] + groups.map { "\($0.label): \($0.values.joined(separator: ", "))" }).joined(separator: " · ")
    }

    /// Værdier i begge lister, i rækkefølgen fra den anbefalede film (vigtigste først). Uden dubletter.
    private static func shared(_ values: [String], _ other: [String]) -> [String] {
        let otherSet = Set(other)
        var seen = Set<String>()
        return values.filter { otherSet.contains($0) && seen.insert($0).inserted }
    }
}
