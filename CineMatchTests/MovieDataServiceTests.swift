//
//  MovieDataServiceTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

struct MovieDataServiceTests {

    /// Bundlen, hvor app-koden (og dermed JSON-filen) ligger.
    /// `Bundle(for:)` kræver en klasse – MockAuthService er en klasse i app-modulet.
    private var appBundle: Bundle { Bundle(for: MockAuthService.self) }

    @Test func bundledJSONDecodesFortyTitles() async throws {
        let service = LocalJSONMovieDataService(bundle: appBundle)

        let titles = try await service.allTitles()

        #expect(titles.count == 40)
        #expect(Set(titles.map(\.id)).count == 40, "Alle MovieLens-id'er skal være unikke")
        #expect(titles.contains { $0.id == 2571 && $0.title == "The Matrix" })
    }

    @Test func missingFileThrowsFileNotFound() async {
        let service = LocalJSONMovieDataService(fileName: "findes_ikke", bundle: appBundle)

        await #expect(throws: MovieDataServiceError.fileNotFound) {
            try await service.allTitles()
        }
    }

    @Test func titlesWithIDsKeepsOrderAndSkipsUnknown() async throws {
        let service = MockMovieDataService()

        let titles = try await service.titles(withIDs: [1258, 999_999, 318])

        #expect(titles.map(\.id) == [1258, 318])
    }
}
