# CineMatch – film-id'er, så modellen spiller sammen med appen

> Til ML-teamet (Anton, Mikkel). Giv hele filen som prompt til jeres AI-assistent.
> Fra Peter, 30/10-2026. Spørgsmål → Peter, før I ændrer formatet.

---

## Prompt

Du hjælper ML-teamet på CineMatch, en iOS-app (SwiftUI), der giver personlige filmanbefalinger.
Modellen kører **lokalt på telefonen**: Python-modellen eksporteres til en JSON-fil (`cinematch_model.json`),
som appen læser. Appen gemmer brugerens likes i Supabase.

**Problemet:** Hver model er trænet på sit eget datasæt med sine egne film-id'er
(Letterboxd-id, MovieLens `movieId` …). Hvis appen gemmer likes med én models id'er,
passer de ikke, når vi skifter model.

**Løsningen:** Appen og databasen bruger kun **TMDB-id** (themoviedb.org, heltal, fx The Matrix = 603).
Hver model beholder sine egne id'er internt, men **skal levere en oversættelse til TMDB-id for hver film.**
Appen oversætter selv ind og ud:

```
Supabase/app:  likes som tmdbId        →  oversæt  →  modellens eget id
Modellen:      top N som eget id       →  oversæt  →  tmdbId  →  plakat, streaming, titel
```

### Regler

1. **Alle film i eksporten har `tmdbId`** (heltal). Mål: mindst 99 % af filmene.
   Film uden `tmdbId` må gerne være med (`null`), men kan ikke likes eller vises med plakat.
2. **Alle startfilm (`starterIDs`) skal have `tmdbId`.** De vises i onboarding.
3. **`tmdbId` er unik.** To film med samme `tmdbId` er en dublet: behold den med flest bedømmelser.
4. **Modellens eget id beholdes i `id`.** Det må være Letterboxd-id, MovieLens-id eller noget tredje.
5. **Kun film.** Ingen serier.
6. **Al tekst, appen viser, er på engelsk** (fx forklaringer og temaer).

### Hvor får I `tmdbId` fra (i denne rækkefølge)

1. **MovieLens:** `links.csv` har `movieId → tmdbId, imdbId`.
2. **Letterboxd-data:** brug en TMDB-kolonne eller -URL, hvis datasættet har én. Letterboxd bygger selv på TMDB.
3. **IMDb-id:** TMDB kan slå IMDb-id op: `GET https://api.themoviedb.org/3/find/{imdb_id}?external_source=imdb_id`.
4. **Sidste udvej:** søg på titel + år: `GET /3/search/movie?query=…&primary_release_year=…`.
   Kun hvis første hit har præcis samme år. Peter har en TMDB-nøgle.

**Kobl aldrig kun på titel.** Det gav før fejl ("Matrix, The" ≠ "The Matrix", "Seven (a.k.a. Se7en)").

### Format i `cinematch_model.json`

Tilføj ét felt på hver film i `films` (i `ml/export_for_app.py`). Resten er uændret, og `formatVersion` forbliver `1`:

```json
{
  "id": 51123,
  "tmdbId": 603,
  "title": "The Matrix",
  "year": 1999,
  "genres": ["Action", "Science Fiction"],
  "director": "Lana Wachowski, Lilly Wachowski",
  "cast": "Keanu Reeves, Laurence Fishburne, …",
  "description": "…",
  "runtime": 136,
  "rating": 3.95,
  "quality": 1.21
}
```

Appen læser allerede `tmdbId`, hvis feltet findes.

### En ny model (fx Mikkels)

Formatet må gerne være et andet, men aftal det med Peter først. Uanset format skal modellen kunne:

- **Input:** en liste af film, brugeren kan lide (vigtigste først), og film, der skal udelukkes
  (allerede liket eller disliket). Appen giver dem som `tmdbId` og oversætter selv til jeres id.
- **Output:** de bedste N film, sorteret, hver med:
  - film-id (eget id eller `tmdbId`)
  - score 0–1
  - en kort begrundelse på engelsk, fx `"Because you liked Se7en · Director: David Fincher"`
- **Eksport:** en fil, hvor hver film har både jeres id og `tmdbId` (regel 1–3).

Ændrer I noget, der bryder det nuværende format, så hæv `formatVersion` (fx til `2`) og sig det til Peter.
Appen afviser filer med en ukendt version i stedet for at gå i stykker.

### Tjek før I afleverer

Kør på den færdige fil:

```python
import json
d = json.load(open("cinematch_model.json", encoding="utf-8"))
films = d["films"]
ids = [f.get("tmdbId") for f in films]
have = [i for i in ids if i is not None]
print(f"Med tmdbId: {len(have)}/{len(films)} ({len(have) / len(films):.1%})")   # mål ≥ 99 %
print("Dubletter:", len(have) - len(set(have)))                                  # skal være 0
by_id = {f["id"]: f for f in films}
missing = [by_id[s]["title"] for s in d["starterIDs"] if by_id[s].get("tmdbId") is None]
print("Startfilm uden tmdbId:", missing)                                         # skal være []
```

Send Peter de tre tal sammen med filen.
