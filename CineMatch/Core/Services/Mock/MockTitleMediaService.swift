//
//  MockTitleMediaService.swift
//  CineMatch
//

/// Falske plakater og tjenester til previews og tests.
/// Bruges også i appen, når TMDB-nøglen mangler i Secrets.plist (så vises pladsholdere).
final class MockTitleMediaService: TitleMediaService {
    static let sampleMedia = TitleMedia(
        tmdbId: 603,
        posterURL: nil,
        streaming: [StreamingProvider(id: 8, name: "Netflix", logoURL: nil)],
        canRentOrBuy: true
    )

    /// Svar pr. film-id. Tom = ingen film har plakat eller tjenester.
    var mediaByTitleID: [Int: TitleMedia]
    /// Film-id'er i den rækkefølge, de blev spurgt om.
    private(set) var requestedIDs: [Int] = []

    init(mediaByTitleID: [Int: TitleMedia] = [:]) {
        self.mediaByTitleID = mediaByTitleID
    }

    func media(for title: Title) async -> TitleMedia? {
        requestedIDs.append(title.id)
        return mediaByTitleID[title.id]
    }
}
