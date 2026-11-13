# CineMatch – sådan virker appen (til ML-teamets agenter)

> Til ML-teamet (Anton, Mikkel). Giv hele filen som prompt til jeres AI-assistent,
> sammen med `docs/ml_prompt_tmdb_id.md` (film-id'er).
> Fra Peter, 30/10-2026. Agenten skal slutte med et svar til Peter i skabelonen nederst.

---

## Prompt

Du hjælper ML-teamet på CineMatch, en iOS-app (SwiftUI), der giver personlige og forklarlige filmanbefalinger.
Anbefalingerne bygger på brugerens egen smag, ikke på popularitet. Peter har lavet appen (frontend).
Din opgave: forstå, hvad appen allerede gør og hvad den skal kunne, og fortæl Peter præcis,
hvad jeres model kan levere, og hvad han skal ændre i appen, for at det spiller sammen.

**Faste regler:**
- Kun **film**. Ingen serier.
- Al tekst, appen viser, er på **engelsk** (begrundelser, temaer, labels).
- Film-id mellem app og model er **TMDB-id** (se `ml_prompt_tmdb_id.md`). Modellen må have egne id'er internt.

---

## 1. Arkitektur

```
┌──────────── iPhone-appen ─────────────────────────────┐
│  Views (SwiftUI) → ViewModels → Services              │
│                                    │                  │
│   cinematch_model.json ──→ OnDeviceRecommender        │  ← modellen kører HER, lokalt
│   (eksporteret fra Python)        (top 5 på telefonen)│
│                                    │                  │
│   TMDB API ──→ plakater + danske streamingtjenester   │
└────────────────────────────────────┼──────────────────┘
                                     ↓
                    Supabase: login + brugerens data
```

- **Der er ingen ML-server.** Python-modellen eksporteres med `ml/export_for_app.py` til `cinematch_model.json`
  (i dag 26 MB, 8.000 film, 25 naboer pr. film). Appen slår op i filen og regner top 5 på telefonen.
- **Supabase** bruges kun til login og til at gemme brugerens data (tabeller nedenfor).
- **TMDB** (themoviedb.org) giver plakater og streamingtjenester i Danmark (Netflix, Viaplay, TV 2 Play …).
  Det klarer appen selv. Modellen behøver ikke vide noget om streaming.

## 2. Modellen i appen i dag (Antons, content-based)

Filen har pr. film: `id`, `tmdbId` (kommer), `title`, `year`, `genres`, `director`, `cast`, `description`,
`runtime`, `rating` (Letterboxd 0–5), `quality` (rating som z-score).
Og pr. film de 25 mest lignende film med similarity, breakdown og fælles træk.

Appen regner præcis som Antons `Recommender.recommend()`:

```
score   = ½ · gennemsnit af similarity til brugerens likes + ½ · bedste enkelt-match     (0–1, vises som match %)
rang    = score + 0.02 · quality
input   = højst 25 likes (nyeste først); likes og dislikes anbefales aldrig
output  = top 5 med: score, "because"-film, breakdown pr. feature, fælles træk
```

- **Features i breakdown:** Story keywords, Director, Cast, Themes, Genres, Writers, Studios, Era, Composer,
  Country, Language, Cinematography, Producers, Editing.
- **Begrundelse** (bygges i appen): `"Because you liked Se7en · Director: David Fincher · Themes: serial killer"`.
- `formatVersion` er `1`. Appen afviser en fil med ukendt version.

## 3. Skærmene

### Bygget og virker

| Skærm | Hvad brugeren gør | Hvad modellen bruges til |
|---|---|---|
| Log in | E-mail og adgangskode (Supabase) | – |
| Your taste (onboarding) | Ét filmkort ad gangen med plakat: **Like / Dislike / Haven't seen / Undo**. Min. 5 likes | `starterIDs`: 48 kendte, godt bedømte film fordelt på genrer |
| For You | Top 5 med plakat, begrundelse og bedste streamingtjeneste | `recommend(liked, excluding)` |

### Designet, ikke bygget endnu (i den rækkefølge)

**A. Streaming-onboarding: "Which services do you have?"**
Brugeren vælger sine tjenester (Netflix, Prime Video, Disney+, HBO Max, Apple TV+, Viaplay, TV 2 Play).
Top 5 viser så "✓ Netflix · in your subscription" eller "Not in your services", med en kontakt til "only my services".
→ **Klares af appen** (TMDB). Modellen skal bare kunne give **flere end 5 kandidater** (fx top 50),
så appen kan filtrere og stadig have 5 tilbage.

**B. Hjemmeskærm: "Your taste" (generel smagsliste)**
Et katalog i rækker, fx *"Because you like slow-burn thrillers"*, *"Dark Nordic crime"*, *"Because you liked Se7en"*.
→ "Because you liked X" kan appen lave med naboerne i dag.
→ Tematiske rækker ("slow-burn thrillers", "Dark Nordic crime") kræver **tags pr. film**
(tone, tempo, temaer, land) og en måde at finde de tags, brugeren kan lide. **Kan jeres model det?**

**C. Daglig smagsscanning: "What do you want to watch tonight?"**
4 hurtige spørgsmål, der bygger videre på den gemte profil og giver en ny top 5 til i aften:

| Spørgsmål | Svar | Hvem klarer det? |
|---|---|---|
| Mood | Laugh · Thrill · Think · Be moved | **Modellen?** Kræver mood-tags pr. film eller en mood-vægt |
| Time | Under 1 hour · About 2 hours · All evening | Appen (filtrerer på `runtime`) |
| Who with | Alone · Partner · Friends · Family | **Modellen/data?** "Family" kræver aldersgrænse eller familie-tag |
| ~~Film or series~~ | Udgår. Kun film | – |

**Top 5 til i aften = generel profil + dagens svar.** Hver film viser match %, en begrundelse,
der nævner dagens humør (fx *"Suspense and a plot twist – fits your mood today"*), og streamingtjeneste.

## 4. Data, appen gemmer om brugeren (Supabase)

| Tabel | Indhold | Status |
|---|---|---|
| `profiles` | bruger-id, oprettet, onboarding færdig | kører |
| `taste_signals` | `movie_id`, `signal` (`like`/`dislike`), `source` (`onboarding`/`feedback`), `created_at` | skrevet, ikke kørt. Skifter til `tmdb_id` |
| `preferences` | streamingtjenester (kommer), evt. favoritgenrer | skrevet |
| `viewing_contexts` | dagens svar: `mood`, `time_available_minutes`, `company` | skrevet |
| `recommendations` | top 5: `rank`, `movie_id`, `score`, `reason`, `explanation` (breakdown), `model_version`, `context_id` | skrevet |

Appen gemmer **det, brugeren gør** (rå data), ikke det, en bestemt model har brug for.
Så kan en ny model bruge de samme data. Det, der mangler, tilføjes med en ny migration.

## 5. Hvad Peter har brug for at vide fra jer

1. **Hvilken model skal appen bruge** (Antons, Mikkels eller en kombination), og kører den stadig lokalt fra en JSON-fil?
2. **Input:** Er likes/dislikes nok, eller skal modellen bruge mere (fx stjerner, "haven't seen", streamingtjenester)?
3. **Output:** Kan modellen give top 50 i stedet for top 5? Med score 0–1, en engelsk begrundelse og breakdown?
4. **Daglig scanning:** Hvordan skal mood (Laugh/Thrill/Think/Be moved) og "Family" påvirke resultatet?
   Leverer modellen tags pr. film, eller skal appen selv mappe fra genrer?
5. **Smagsrækker på hjemmeskærmen:** Kan modellen give tags/temaer pr. film og finde brugerens yndlingstemaer?
6. **Filen:** Ændres formatet? Ny `formatVersion`? Forventet størrelse (i dag 26 MB)?
7. **Film-id:** Har hver film `tmdbId` (se `ml_prompt_tmdb_id.md`)?

---

## Svar til Peter (udfyld og send)

```
MODEL
- Navn/version:
- Kører i appen som: [JSON-fil som i dag / andet: …]
- formatVersion: [1 uændret / 2: hvad er nyt]

INPUT, modellen skal have
- …

OUTPUT, modellen leverer pr. film
- id: [tmdbId / eget id + tmdbId i filen]
- score 0–1: [ja/nej]
- begrundelse på engelsk: [ja/nej, eksempel: …]
- breakdown/fælles træk: [ja/nej]
- antal kandidater: [5 / 50 / …]

NYE FELTER PR. FILM I EKSPORTEN
- fx moods: ["thrill", "think"], tags: ["slow-burn", "dark"], ageRating: "15"
- …

DAGLIG SCANNING
- Mood: [modellen håndterer det sådan her: … / appen skal selv …]
- Family: …

HJEMMESKÆRM (tematiske rækker)
- …

PETER SKAL ÆNDRE I APPEN
1. …
2. …

TJEK (fra ml_prompt_tmdb_id.md)
- Med tmdbId: …/… (…%)   Dubletter: …   Startfilm uden tmdbId: …
```
