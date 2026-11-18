//
//  Verdict.swift
//  CineMatch
//

/// Brugerens dom over én film. Bruges ALLE steder, brugeren bedømmer: Swipe, "Seen it" og Search.
///
/// `rawValue` er det tal, modellerne får som input (aftalt med ML-holdet):
///
/// | Knap         | Værdi |
/// |--------------|-------|
/// | Haven't seen | 0     |
/// | Horrible     | 1     |
/// | Bad          | 2     |
/// | Great        | 3     |
/// | Fantastic    | 5     |
///
/// Der er bevidst ingen 4: "Fantastic" skal veje tydeligt mere end "Great".
/// Skal skalaen ændres, er det KUN her (og i migration 0005's check).
nonisolated enum Verdict: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case notSeen = 0
    case horrible = 1
    case bad = 2
    case great = 3
    case fantastic = 5

    var id: Int { rawValue }

    /// Tallet, modellerne får.
    var score: Int { rawValue }

    /// De fire domme for en film, brugeren HAR set. Rækkefølgen er knapperne fra venstre mod højre.
    static let seenOptions: [Verdict] = [.horrible, .bad, .great, .fantastic]

    /// Teksten på knappen.
    var label: String {
        switch self {
        case .notSeen: "Haven't seen"
        case .horrible: "Horrible"
        case .bad: "Bad"
        case .great: "Great"
        case .fantastic: "Fantastic"
        }
    }

    var systemImage: String {
        switch self {
        case .notSeen: "eye.slash"
        case .horrible: "hand.thumbsdown.fill"
        case .bad: "hand.thumbsdown"
        case .great: "hand.thumbsup"
        case .fantastic: "heart.fill"
        }
    }

    /// False for "Haven't seen". Kun sete film er input til modellerne.
    var isSeen: Bool { self != .notSeen }

    /// Great eller Fantastic. Antons nuværende model tager kun en liste af film, brugeren kan lide.
    var isPositive: Bool { self == .great || self == .fantastic }

    /// Læser en gemt værdi. Præcis 0, 1, 2, 3 eller 5 er den nye skala.
    /// Andre værdier er gamle ½–5-stjerner fra før skalaen og oversættes til den nærmeste dom.
    init?(storedScore value: Double) {
        guard value.isFinite, (0...5).contains(value) else { return nil }
        if let exact = Verdict(rawValue: Int(value)), Double(exact.rawValue) == value {
            self = exact
            return
        }
        switch value {
        case ..<1.5: self = .horrible
        case ..<3: self = .bad
        case ..<4.5: self = .great
        default: self = .fantastic
        }
    }
}
