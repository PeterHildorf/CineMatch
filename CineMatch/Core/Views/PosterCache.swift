//
//  PosterCache.swift
//  CineMatch
//

import UIKit

/// Plakater i hukommelsen, så de kan hentes i forvejen og vises med det samme.
///
/// `AsyncImage` gemmer ikke billeder pålideligt og henter først, når billedet vises.
/// Her hentes plakaten én gang, afkodes uden for main thread og ligger klar til næste gang.
final class PosterCache {
    static let shared = PosterCache()

    private let images = NSCache<NSURL, UIImage>()
    /// Hentninger i gang, så samme plakat ikke hentes to gange samtidig.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        images.countLimit = 200
    }

    /// Plakaten, hvis den allerede er hentet. Bruges, så kortet kan vises uden pladsholder.
    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    /// Henter plakaten (eller giver den gemte). `nil` = kunne ikke hentes.
    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }

        // En selvstændig Task, så hentningen gøres færdig og gemmes, selv om skærmen forsvinder.
        let task = inFlight[url] ?? Task { await Self.download(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Starter hentningen uden at vente på den.
    func prefetch(_ url: URL?) {
        guard let url, cachedImage(for: url) == nil, inFlight[url] == nil else { return }
        Task { _ = await image(for: url) }
    }

    /// Henter og afkoder billedet uden for main thread, så swipe ikke hakker.
    @concurrent
    private nonisolated static func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300 else { return nil }
        return await UIImage(data: data)?.byPreparingForDisplay()
    }
}
