# CineMatch – kontrakt mellem app og ML-service

> Udkast 13/10 – skal godkendes af ML-teamet.
> Opdateret 23/10: **al tekst i appen er på engelsk**, også `reason`.
> Opdateret 23/10: **onboarding er lavet om.** Brugeren vælger film, han kan lide (likes), i stedet for at give 1–5 stjerner. `taste_signals` erstatter `ratings`, så input passer direkte til Antons model (`recommend(liked_ids)`).
> SQL: `supabase/migrations/0001_initial_schema.sql` + `0002_taste_signals.sql`

## Overblik (variant A)

1. I onboarding vælger brugeren film, han kan lide (og evt. film, der ikke er noget for ham). Appen gemmer dem i `taste_signals`.
2. Appen kalder `POST /recommend` med brugerens access token ("Get recommendations").
3. ML-servicen læser brugerens `taste_signals` fra Supabase.
4. ML-servicen kører modellen med brugerens likes og skriver top 5 til `recommendations`.
5. Appen læser `recommendations` og viser dem.

Appen laver ingen beregninger. ML-servicen gemmer intet selv.

## Sprog

Appen er på engelsk. Al tekst, som ML-servicen leverer og appen viser direkte (`reason`, `message`), skal derfor være på engelsk.

## Fælles ID

`movie_id` er **altid MovieLens `movieId`** (heltal). Datasættet er `merged_datasets.csv` (MovieLens + Letterboxd, 71.828 film).
Det skal kobles på `tmdbId`/`imdbId` i stedet for titel. Se `docs/ml_team_brief.md`.

Antons model bruger internt Letterboxd `id`. ML-servicen oversætter `movieId` ↔ Letterboxd `id` begge veje. Appen ser kun `movieId`.
Indekset bør kun bygges over film, der har et `movieId`, så alt, modellen anbefaler, kan slås op i `movies`.

Onboardingens plakatgitter viser ca. 40 **varierede** film (forskellige genrer og årtier, ikke kun blockbusters) fra `CineMatch/Core/Resources/movielens_titles.json`.
Brugeren kan også søge efter sine egne favoritter i hele `movies`. **Alle film i gitteret skal findes i modellens indeks.**

## Tabeller

| Tabel | Skrives af | Læses af | Indhold |
|---|---|---|---|
| `movies` | ML (import af datasættet) | appen, ML | `movie_id`, `tmdb_id`, `imdb_id`, `title`, `year`, `genres`, `description`, `runtime_minutes`, `letterboxd_rating`, `themes` |
| `profiles` | Supabase (trigger ved signup), appen | appen | `id`, `onboarding_completed_at` |
| `taste_signals` | appen | ML | `user_id`, `movie_id`, `signal` (`like` / `dislike`), `source` (`onboarding` / `feedback`), `created_at` |
| `preferences` | appen | ML | `favorite_genres text[]` (senere) |
| `viewing_contexts` | appen | ML | `mood`, `time_available_minutes`, `company` (senere) |
| `recommendations` | **kun ML** | appen | `user_id`, `rank` (1–5), `movie_id`, `score`, `reason` (engelsk tekst), `explanation` (jsonb, valgfri), `model_version`, `context_id`, `created_at` |

`ratings` (1–5 stjerner) udgår. Tabellen kan slettes, når `taste_signals` er i brug.

### `taste_signals`

```sql
create table public.taste_signals (
    user_id     uuid not null references auth.users (id) on delete cascade,
    movie_id    integer not null,                                   -- MovieLens movieId
    signal      text not null check (signal in ('like', 'dislike')),
    source      text not null default 'onboarding' check (source in ('onboarding', 'feedback')),
    created_at  timestamptz not null default now(),
    primary key (user_id, movie_id)
);
-- RLS: brugeren må læse/skrive sine egne rækker (som de andre tabeller).
```

- Én række pr. (bruger, film). Skifter brugeren mening, opdateres rækken. Fjernes et like, slettes rækken.
- `source = 'feedback'` bruges senere til tommel op/ned på anbefalingerne. Samme tabel, ingen ny kontrakt.

### Sådan bruger ML-servicen signalerne

- `liked` = alle film med `signal = 'like'`, nyeste først, højst 25 (modellens `MAX_LIKED`). Listen sendes direkte til `recommender.recommend(liked)`.
- `dislike` bruges ikke af modellen endnu, men **alle film i `taste_signals` (like og dislike) filtreres fra resultatet**.
- Under 5 likes → 422 `too_few_likes`.

### `explanation` (valgfri)

Modellens `breakdown` gemt som jsonb, så appen kan vise match-score og søjler:
```json
[{"feature": "director", "label": "Director", "value": 0.13}, {"feature": "theme", "label": "Themes", "value": 0.09}]
```

**RLS:** Appen kan kun se og ændre sine egne rækker og må kun *læse* `recommendations`.
ML-servicen bruger **service role key**, som går uden om RLS. Den nøgle ligger kun på serveren (miljøvariabel), aldrig i appen og aldrig i git.

**Skrivning af anbefalinger:** For den pågældende bruger sletter ML-servicen de gamle rækker i `recommendations` og indsætter nye med `rank` 1–5. Det sker i én transaktion eller i ét `upsert` på `(user_id, rank)`.

## Endpoint: `POST /recommend`

**Request**
```
POST {ML_BASE_URL}/recommend
Authorization: Bearer <brugerens Supabase access token>
Content-Type: application/json

{ "context_id": null }          // uuid fra viewing_contexts, eller null
```

ML-servicen finder `user_id` ved at verificere tokenet, fx med `supabase.auth.get_user(token)` i Python.
Den må **ikke** stole på et `user_id` i request-body.

**Svar ved succes:** `200 OK`, efter at rækkerne er skrevet til `recommendations`
```json
{ "status": "ok", "count": 5, "model_version": "2026-10-23-a" }
```
Appen læser derefter `recommendations`. Svaret indeholder ikke selve anbefalingerne, så der er kun én sandhed: tabellen.

**Fejl**

| Status | `error` | Betydning | Appen viser |
|---|---|---|---|
| 401 | `invalid_token` | Token mangler, er ugyldigt eller udløbet | Logger brugeren ud eller forsøger igen efter refresh |
| 422 | `too_few_likes` | Under 5 likes | "Pick at least 5 movies you love" |
| 503 | `model_not_ready` | Modellen er ikke indlæst, eller serveren starter op (Render free tier kan tage ~1 min) | "Recommendations aren't ready yet – try again" |
| 500 | `internal` | Andet | "Something went wrong" + "Try again" |

Fejlbody: `{ "error": "too_few_likes", "message": "..." }` (`message` på engelsk)

**Timeout:** Appen venter op til 60 sekunder (koldstart på Render).

## Natlig beregning

GitHub Actions kører den samme beregning for alle brugere hver nat og skriver til `recommendations`. Appen mærker ingen forskel.

## Åbne spørgsmål til ML-teamet

1. **URL:** Kører servicen på Render, eller lokalt på en af jeres computere? Hvis den kører lokalt, skal iPhonen kunne nå den (samme Wi-Fi + IP, eller ngrok).
2. **`reason`:** Kan modellen give en kort begrundelse som **engelsk** tekst, fx "Because you liked Se7en · Director: David Fincher · Themes: serial killer"? Den kan bygges direkte ud fra modellens `because` og `shared`. Hvis ikke, viser appen bare genrerne.
3. **Filmkatalog:** ~~Hvordan kender appen titlerne?~~ Løst: ML-teamet fylder `movies` i Supabase, og appen slår op dér. Åbent: kan alle 71.828 film anbefales, eller filtrerer ML?
4. ~~**Skala:** Er 0.5–5.0 OK?~~ Udgået: appen sender likes/dislikes i stedet for stjerner.
5. **Minimum likes:** Er 5 nok? Og bruger I højst 25 likes (`MAX_LIKED`)?
6. **Film brugeren har markeret:** ~~Skal de udelukkes?~~ Ja: ML filtrerer alle film i `taste_signals` fra.
7. **`popularity_boost`:** Kan den sættes til 0? Visionen er smag frem for popularitet.
8. **Dislikes:** Kan modellen senere trække film ned, der ligner brugerens dislikes?
