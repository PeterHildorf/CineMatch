//
//  Verdict.swift
//  CineMatch
//

import Foundation

/// Brugerens dom over én film. Bruges ALLE steder, brugeren bedømmer: Swipe, "Seen it" og Search.
///
/// `rawValue` er det tal, modellerne får som input (aftalt med ML-holdet):
///
/// | Knap         | Værdi |
/// |--------------|-------|
/// | Haven't seen | 0     |
/// | Horrible     | 1     |
/// | Bad          | 2     |
/// | Neutral      | 3     |
/// | Great        | 4     |
/// | Fantastic    | 5     |
///
/// "Haven't seen" er ikke en dom: filmen springes over og kommer først igen i Swipe
/// efter `notSeenCooldown`. Den er aldrig modelinput.
/// Skal skalaen ændres, er det her (og i migration 0006).
nonisolated enum Verdict: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case notSeen = 0
    case horrible = 1
    case bad = 2
    case neutral = 3
    case great = 4
    case fantastic = 5

    var id: Int { rawValue }

    /// Tallet, modellerne får.
    var score: Int { rawValue }

    /// De fem domme for en film, brugeren HAR set. Rækkefølgen er knapperne fra venstre mod højre.
    static let seenOptions: [Verdict] = [.horrible, .bad, .neutral, .great, .fantastic]

    /// Så længe går der, før en film, brugeren ikke har set, kan dukke op i Swipe igen.
    static let notSeenCooldown: TimeInterval = 14 * 24 * 60 * 60

    /// Teksten på knappen.
    var label: String {
        switch self {
        case .notSeen: "Haven't seen"
        case .horrible: "Horrible"
        case .bad: "Bad"
        case .neutral: "Neutral"
        case .great: "Great"
        case .fantastic: "Fantastic"
        }
    }

    var systemImage: String {
        switch self {
        case .notSeen: "eye.slash"
        case .horrible: "hand.thumbsdown.fill"
        case .bad: "hand.thumbsdown"
        case .neutral: "minus.circle"
        case .great: "hand.thumbsup"
        case .fantastic: "heart.fill"
        }
    }

    /// False for "Haven't seen". Kun sete film er input til modellerne.
    var isSeen: Bool { self != .notSeen }

    /// Great eller Fantastic. Antons nuværende model tager kun en liste af film, brugeren kan lide.
    var isPositive: Bool { self == .great || self == .fantastic }

    /// Læser en gemt værdi. Hele tal 0–5 er skalaen.
    /// Halve værdier er gamle ½–5-stjerner fra før 0005 og oversættes til den nærmeste dom.
    init?(storedScore value: Double) {
        guard value.isFinite, (0...5).contains(value) else { return nil }
        if let exact = Verdict(rawValue: Int(value)), Double(exact.rawValue) == value {
            self = exact
            return
        }
        switch value {
        case ..<1.5: self = .horrible
        case ..<2.5: self = .bad
        case ..<3.5: self = .neutral
        case ..<4.5: self = .great
        default: self = .fantastic
        }
    }
}
