//
//  DemoData.swift
//  CineMatch
//

import Foundation

/// Mockdata, så hele appens UI kan ses uden modelfiler, Supabase eller netværk.
///
/// Bruges af `AppContainer.demo()` (start appen med `-demo`, se schemeets "Arguments") og af previews.
/// Film-id = TMDB-id, så `TMDBMediaService` henter rigtige plakater, hvis TMDB-nøglen er sat op.
/// Uden nøglen bruges `MockTitleMediaService.demo` (pladsholdere + streamingtjenester).
enum DemoData {
    static let titles: [Title] = [
        film(807, "Se7en", 1995, ["Crime", "Mystery", "Thriller"], "David Fincher", "Brad Pitt, Morgan Freeman", 127,
             "Two homicide detectives are on a desperate hunt for a serial killer whose crimes are based on the seven deadly sins."),
        film(27205, "Inception", 2010, ["Action", "Science Fiction", "Adventure"], "Christopher Nolan", "Leonardo DiCaprio, Elliot Page", 148,
             "A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea."),
        film(496243, "Parasite", 2019, ["Comedy", "Thriller", "Drama"], "Bong Joon-ho", "Song Kang-ho, Choi Woo-shik", 133,
             "All unemployed, Ki-taek's family takes a peculiar interest in the wealthy Park family."),
        film(129, "Spirited Away", 2001, ["Animation", "Family", "Fantasy"], "Hayao Miyazaki", "Rumi Hiiragi, Miyu Irino", 125,
             "A young girl wanders into a world ruled by gods, witches and spirits, where humans are changed into beasts."),
        film(155, "The Dark Knight", 2008, ["Drama", "Action", "Crime"], "Christopher Nolan", "Christian Bale, Heath Ledger", 152,
             "Batman raises the stakes in his war on crime – until a criminal mastermind known as the Joker appears."),
        film(680, "Pulp Fiction", 1994, ["Thriller", "Crime"], "Quentin Tarantino", "John Travolta, Uma Thurman", 154,
             "The lives of two mob hitmen, a boxer, a gangster and his wife intertwine in four tales of violence and redemption."),
        film(313369, "La La Land", 2016, ["Comedy", "Drama", "Romance", "Music"], "Damien Chazelle", "Ryan Gosling, Emma Stone", 128,
             "A jazz pianist and an aspiring actress fall in love while pursuing their dreams in Los Angeles."),
        film(419430, "Get Out", 2017, ["Mystery", "Thriller", "Horror"], "Jordan Peele", "Daniel Kaluuya, Allison Williams", 104,
             "A young Black man visits his white girlfriend's family estate, where his uneasiness turns into something far worse."),
        film(76341, "Mad Max: Fury Road", 2015, ["Action", "Adventure", "Science Fiction"], "George Miller", "Tom Hardy, Charlize Theron", 121,
             "In a post-apocalyptic wasteland, Max teams up with Furiosa to flee a tyrant and his army across the desert."),
        film(194, "Amélie", 2001, ["Comedy", "Romance"], "Jean-Pierre Jeunet", "Audrey Tautou, Mathieu Kassovitz", 122,
             "A shy waitress in Paris decides to change the lives of those around her for the better – while struggling with her own isolation."),
        film(545611, "Everything Everywhere All at Once", 2022, ["Action", "Adventure", "Science Fiction"], "Daniel Kwan, Daniel Scheinert", "Michelle Yeoh, Ke Huy Quan", 140,
             "A laundromat owner discovers she must connect with parallel-universe versions of herself to stop a powerful being."),
        film(244786, "Whiplash", 2014, ["Drama", "Music"], "Damien Chazelle", "Miles Teller, J.K. Simmons", 107,
             "A promising young drummer enrolls at a cut-throat music conservatory, where an instructor will stop at nothing to realise his potential."),
        film(329865, "Arrival", 2016, ["Drama", "Science Fiction", "Mystery"], "Denis Villeneuve", "Amy Adams, Jeremy Renner", 116,
             "A linguist works with the military to communicate with alien lifeforms after twelve mysterious spacecraft appear."),
        film(546554, "Knives Out", 2019, ["Comedy", "Crime", "Mystery"], "Rian Johnson", "Daniel Craig, Ana de Armas", 131,
             "A detective investigates the death of a patriarch of an eccentric, combative family."),
        film(1949, "Zodiac", 2007, ["Crime", "Drama", "Mystery"], "David Fincher", "Jake Gyllenhaal, Mark Ruffalo", 157,
             "A cartoonist becomes obsessed with tracking down the Zodiac killer in 1970s San Francisco."),
        film(146233, "Prisoners", 2013, ["Drama", "Thriller", "Crime"], "Denis Villeneuve", "Hugh Jackman, Jake Gyllenhaal", 153,
             "When his daughter goes missing, a desperate father takes matters into his own hands."),
        film(120467, "The Grand Budapest Hotel", 2014, ["Comedy", "Drama"], "Wes Anderson", "Ralph Fiennes, Tony Revolori", 100,
             "The adventures of a legendary concierge at a famous European hotel and the lobby boy who becomes his most trusted friend."),
        film(391713, "Lady Bird", 2017, ["Comedy", "Drama"], "Greta Gerwig", "Saoirse Ronan, Laurie Metcalf", 94,
             "A high-school senior in Sacramento navigates a turbulent relationship with her mother over one formative year."),
        film(493922, "Hereditary", 2018, ["Horror", "Mystery", "Thriller"], "Ari Aster", "Toni Collette, Alex Wolff", 127,
             "After the family matriarch passes away, a grieving family is haunted by tragic and disturbing occurrences."),
        film(346648, "Paddington 2", 2017, ["Adventure", "Comedy", "Family"], "Paul King", "Ben Whishaw, Hugh Grant", 104,
             "Paddington picks up odd jobs to buy the perfect present – until it is stolen and he is wrongly accused."),
        film(37799, "The Social Network", 2010, ["Drama"], "David Fincher", "Jesse Eisenberg, Andrew Garfield", 120,
             "The story of how Harvard student Mark Zuckerberg created Facebook – and the lawsuits that followed."),
        film(153, "Lost in Translation", 2003, ["Drama", "Comedy", "Romance"], "Sofia Coppola", "Bill Murray, Scarlett Johansson", 102,
             "A faded movie star and a neglected young woman form an unlikely bond in Tokyo."),
        film(438631, "Dune", 2021, ["Science Fiction", "Adventure"], "Denis Villeneuve", "Timothée Chalamet, Zendaya", 155,
             "Paul Atreides travels to the most dangerous planet in the universe to ensure the future of his family and people."),
        film(152601, "Her", 2013, ["Romance", "Science Fiction", "Drama"], "Spike Jonze", "Joaquin Phoenix, Scarlett Johansson", 126,
             "A lonely writer develops an unlikely relationship with an operating system designed to meet his every need."),
    ]

    /// Swipe-bunken: de første 14 film. Resten er "skjulte" anbefalinger, så Today viser film, man ikke har swipet.
    static var swipeTitles: [Title] { Array(titles.prefix(14)) }

    /// Anbefalinger i den rækkefølge, en "model" ville give dem. Både film fra Swipe-bunken og nye.
    static let recommendations: [Recommendation] = [
        rec(1949, "Because you liked Se7en · Director: David Fincher"),
        rec(146233, "Because you liked Se7en · Themes: missing child, obsession"),
        rec(438631, "Because you liked Arrival · Director: Denis Villeneuve"),
        rec(120467, "Because you liked Amélie · Mood: whimsical, feel-good"),
        rec(152601, "Because you liked La La Land · Themes: loneliness, love"),
        rec(37799, "Because you liked Whiplash · Themes: ambition"),
        rec(493922, "Because you liked Get Out · Mood: slow-burn horror"),
        rec(391713, "Because you liked La La Land · Genre: coming-of-age"),
        rec(346648, "Because you liked Spirited Away · Mood: feel-good"),
        rec(153, "Because you liked Amélie · Mood: quiet, bittersweet"),
        rec(329865, "Because you liked Inception · Genre: cerebral sci-fi"),
        rec(546554, "Because you liked Parasite · Themes: class, family"),
        rec(545611, "Because you liked Inception · Themes: multiverse"),
        rec(244786, "Because you liked La La Land · Director: Damien Chazelle"),
        rec(76341, "Because you liked The Dark Knight · Genre: action"),
        rec(194, "Because you liked Spirited Away · Mood: whimsical"),
    ].enumerated().map { index, recommendation in
        Recommendation(rank: index + 1, movieID: recommendation.movieID, score: 0.95 - Double(index) * 0.03, reason: recommendation.reason)
    }

    /// Streamingtjenester pr. film, så "Where to watch" og "Only my services" kan ses.
    static let media: [Int: TitleMedia] = {
        let netflix = StreamingProvider(id: 8, name: "Netflix", logoURL: nil)
        let hbo = StreamingProvider(id: 1899, name: "HBO Max", logoURL: nil)
        let viaplay = StreamingProvider(id: 76, name: "Viaplay", logoURL: nil)
        let disney = StreamingProvider(id: 337, name: "Disney+", logoURL: nil)
        let prime = StreamingProvider(id: 9, name: "Prime Video", logoURL: nil)
        let services: [[StreamingProvider]] = [[netflix], [hbo], [viaplay, netflix], [disney], [prime], [], [hbo, prime]]
        return Dictionary(uniqueKeysWithValues: titles.enumerated().map { index, title in
            let streaming = services[index % services.count]
            return (title.id, TitleMedia(tmdbId: title.tmdbId ?? title.id, posterURL: nil, streaming: streaming, canRentOrBuy: true))
        })
    }()

    // MARK: - Hjælpere

    private static func film(
        _ tmdbId: Int, _ title: String, _ year: Int, _ genres: [String],
        _ director: String, _ cast: String, _ runtime: Int, _ overview: String
    ) -> Title {
        Title(id: tmdbId, tmdbId: tmdbId, title: title, year: year, genres: genres,
              director: director, cast: cast, overview: overview, runtimeMinutes: runtime)
    }

    private static func rec(_ movieID: Int, _ reason: String) -> Recommendation {
        Recommendation(rank: 0, movieID: movieID, score: nil, reason: reason)
    }
}

extension MockTitleMediaService {
    /// Streamingtjenester til alle demo-film (ingen plakater – dem giver TMDB).
    static var demo: MockTitleMediaService { MockTitleMediaService(mediaByTitleID: DemoData.media) }
}
