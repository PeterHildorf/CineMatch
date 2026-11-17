//
//  RecommendationEventLogger.swift
//  CineMatch
//

/// Logger anbefalinger, visninger og "Seen it", så modellernes præcision kan måles.
/// Én logger pr. pipeline – den ved selv, om det er stars, swipe eller search.
protocol RecommendationEventLogger: Sendable {
    /// Sender eventet i baggrunden, i den rækkefølge det blev logget.
    /// Kaster aldrig og venter ikke: målinger må aldrig gøre appen langsommere eller vise fejl.
    func log(_ event: RecommendationEvent)
}
