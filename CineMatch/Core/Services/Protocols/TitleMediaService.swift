//
//  TitleMediaService.swift
//  CineMatch
//

/// Henter plakat og streamingtjenester til en film.
///
/// Returnerer `nil`, hvis vi intet ved (ukendt film, ingen TMDB-nøgle eller netværksfejl).
/// Det er aldrig en fejl for brugeren: kortet viser bare en pladsholder.
protocol TitleMediaService: Sendable {
    func media(for title: Title) async -> TitleMedia?
}
