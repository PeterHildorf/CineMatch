# CineMatch – Agil projektplan

> Levende dokument. Opdatér status efter hvert sprint.
> Prompts til hver fase ligger i `CineMatch_prompts.md`.

## Vision
CineMatch giver personlige, **forklarlige** film- og serieanbefalinger ud fra din smag, ikke ud fra hvad der er populært.
Appen er en *tynd klient*: den gemmer brugerens input i Supabase og viser de anbefalinger, ML-servicen skriver tilbage.

## Sådan arbejder vi
- **Hvem skriver koden (fra 23/10):** Claude skriver koden (app, SQL og evt. ML-service) med korte danske kommentarer. Jeg (Peter) reviewer, tester på iPhone og godkender, før der committes.
- **Sprog (fra 23/10):** Al tekst i appen er på engelsk. Kommentarer i koden må gerne være på dansk.
- **Arkitektur (fra 23/10, erstatter variant A):** Modellen kører **lokalt i appen**. Der er ingen ML-server. Antons model eksporteres med `ml/export_for_app.py` til `cinematch_model.json`, som ligger i appen. `OnDeviceRecommender` laver top 5 på telefonen. Supabase bruges kun til login og til at gemme brugerens likes (`taste_signals`). Film-ID er Letterboxd `id`. Kontrakten står i `docs/ml_contract.md`.
- **Model (fra 23/10):** Antons content-based model (`Antons_Model.py`). Den tager en liste af film, brugeren kan lide, og giver lignende film med forklaring. Derfor bygger onboarding på **likes** i stedet for 1–5 stjerner.
- **Sprints på ca. 1 uge** (2–4 lange sessioner à 1–2 timer).
- Hvert sprint har **ét mål** og ender med noget, der **virker og kan vises** (en "demo").
- **Lodrette skiver:** hellere en lille feature hele vejen igennem (UI → ViewModel → service → Supabase) end store lag, der først virker til sidst.
- Efter hvert sprint: en kort **retro** (3 spørgsmål nederst) og opdatering af denne fil.

### Definition of Done (gælder alle user stories)
- [ ] Projektet bygger uden fejl
- [ ] Featuren er afprøvet på iPhone (rigtig enhed eller simulator)
- [ ] ViewModels og services har unit tests
- [ ] Ingen hemmeligheder i git (`Secrets.plist` er ignoreret)
- [ ] Committed i git med en beskrivende besked

---

## Beslutninger 30/10

- **Al tekst i appen er på engelsk. Altid.**
- **Kun film.** Ingen serier ("Film or series" er taget ud af designet).
- **Film-id er TMDB-id** i appen og Supabase. Hver model leverer en oversættelse (se `docs/ml_prompt_tmdb_id.md`).
- **Onboarding: begge dele.** Swipe giver like/dislike, og brugeren kan give ½–5 stjerner (Mikkels model). Stjerner gemmes som stjerner.
- **UI bygges mod mock-services nu**, så modellerne kan sættes ind senere. Rækkefølge: streaming → hjemmeskærm → daglig scanning.
- **Design (mørkt tema, orange) kommer senere.**
- ML-teamets svar: kontrakt v2 (`formatVersion: 2`, moods, tags, aldersgrænse, 50 kandidater). Se `docs/ml_prompt_app_overview.md`.

### Streaming (30/10) ✅ bygget, skal testes
- [x] `StreamingService` (7 danske tjenester), `PreferencesService` (lokal i `UserDefaults` + mock)
- [x] "Which services do you have?" vises første gang efter login og i kontomenuen
- [x] For You: "✓ Netflix · in your subscription" / "not in your services" + kontakten "Only my services"
- [x] Modellen giver 50 kandidater, appen viser 5 (efter filter)
- [ ] Migration `0003_streaming_preferences.sql` skrevet, ikke kørt (Supabase-version mangler)

### Mikkels model (30/10) ✅ bygget, skal testes
- [x] `cinematch_mf.json` i appen (9.014 film, TMDB-id). Doku: `ml/mikkel_mf/INTEGRATION.md`
- [x] `MatrixFactorizationRecommender` (fold-in, 17×17-løser) + `MFModelStore`, `MFMovieDataService`, `MFRecommendationService`
- [x] Testet mod Mikkels 4 referencecases fra Python (tolerance 1e-6) + SHA-256 af modelfilen
- [x] **Flow (30/10):** tjenester → "Rate movies" (liste med ½–5 stjerner, Mikkel) → "Swipe" (like/dislike, Anton) → faner
- [x] Begge modeller kører side om side med hver deres svar: faner "Rate", "Star picks", "Swipe", "Swipe picks". Top 10 på begge
- [ ] `taste_signals` i Supabase: tilføj `rating numeric(2,1)` og `'neutral'` (migration 0004)
- [ ] Mikkel: kataloget har serier (fx "The OA", "13 reasons why", "Cosmos") og 30 titler uden år. Skal renses
- [ ] Ingen begrundelse eller match-% fra modellen. Kortet viser "Based on your star ratings"

## Status-overblik

| Sprint | Mål | Fase i prompts | Status |
|---|---|---|---|
| 0 | Login-skelet med mock | Fase 2 (del) | ✅ Færdig |
| 1 | Rigtigt login mod Supabase (e-mail) | Fase 2 | ✅ Færdig |
| 1½ | **Første kæde med Antons model:** vælg favoritter → se top 5 | Fase 1, 3, 4 (minimum) | 🔜 I gang |
| 2 | Filmdata i appen | Fase 1 | ⬜ (minimum i 1½) |
| 3 | Database + gem smagsdata (`taste_signals`) | Fase 3 (del 1) | ⬜ |
| 4 | Onboarding-flow med favoritter | Fase 3 (del 2) | ⬜ |
| 5 | Anbefalinger (med mock-ML) | Fase 4 (del 1) | ⬜ |
| 6 | Rigtige anbefalinger + kontekst | Fase 4 (del 2) | ⬜ |
| 7 | Profil, nulstilling, tabs | Fase 5 | ⬜ |
| 8 | Kvalitet & release-klar | Fase 6 | ⬜ |

---

## Sprint 0 – Login-skelet ✅
**Leveret:** `AuthService`-protokol, `SupabaseAuthService`, `MockAuthService`, `AuthViewModel`, `SignInView`, `AppContainer`, `RootView`, Supabase-pakken, tests skrevet.
**Rest:** test-targetet gik tabt i Xcode-crash (genskabes i sprint 1).

---

## Sprint 1 – Rigtigt login ✅
**Ændret:** Vi droppede Sign in with Apple og bruger e-mail + adgangskode i Supabase (ingen betalte tjenester). Login virker, og brugeren oprettes i Supabase (13/10). Opgaverne nedenfor om Apple er ikke længere aktuelle.

**Oprindeligt mål:** Jeg kan logge ind med mit Apple-ID på min iPhone, og Supabase kender mig.

**User stories**
1. *Som bruger vil jeg logge ind med Apple, så jeg ikke skal huske endnu en adgangskode.*
   - Kriterier: Apple-arket vises → jeg lander på velkomstskærmen → brugeren findes i Supabase → Authentication → Users.
2. *Som bruger vil jeg forblive logget ind, når jeg lukker og åbner appen.*
   - Kriterier: genstart af appen springer login over. Uden internet bliver jeg ikke smidt ud.
3. *Som bruger vil jeg kunne logge ud.*
4. *Som udvikler vil jeg have kørende tests for login.* (genskab test-target)

**Opgaver**
- [ ] Supabase: slå Apple-provider til, indsæt Bundle ID under Client IDs
- [ ] Xcode: vælg Team, sæt eget Bundle ID (erstat `devplaceholder…`)
- [ ] Opret `App/Secrets.plist` ud fra `Secrets.example.plist`
- [ ] Kør på rigtig iPhone (simulatoren er ustabil på denne Mac)
- [ ] Genskab `CineMatchTests`-target og kør de 7 tests

**Demo:** Log ind på iPhone → luk app → åbn igen → stadig logget ind → log ud.

---

## Sprint 1½ – Første kæde med Antons model 🔜
**Mål:** Hele kæden kan testes med Antons model: vælg favoritter → "Get recommendations" → se top 5.
Det er det mindste, der skal til fra sprint 2–5. Humør, streamingtjenester og pæn onboarding kommer bagefter.

**Ændret 23/10:** Modellen kører lokalt i appen (ingen server). Antons model tager en liste af film, brugeren kan lide, så bedøm-skærmen bliver til en "pick your favorites"-skærm med likes, og `ratings` erstattes af `taste_signals`. Appen er på engelsk.

**Opgaver**
- [x] `ml/export_for_app.py`: eksporterer Antons model til `cinematch_model.json` (testet på testdata: samme rækkefølge som Antons `recommend()`)
- [x] `Core/ML`: `ModelFile`, `OnDeviceRecommender`, `ModelStore` + `OnDeviceMovieDataService`, `OnDeviceRecommendationService` + tests
- [x] `AppContainer.live()` bruger modellen, når `cinematch_model.json` ligger i appen (ellers mocks)
- [x] **Anton kører eksporten**, og `cinematch_model.json` lægges i `CineMatch/Core/Resources/` (8.000 film, 23/10)
- [ ] Første test på iPhone: bedøm 5+ film (4–5 stjerner = like) → "Beregn nu" → top 5 fra modellen
- [x] `docs/ml_contract.md` opdateret til lokal model
- [~] Migration `0002_taste_signals.sql` skrevet, ikke kørt. Køres, når appen gemmer likes i Supabase
- [x] `Rating` → `TasteSignal` (`.like` / `.dislike`), `RatingService` → `TasteSignalService` (mock). Supabase-version mangler
- [x] `RateMoviesViewModel` → `TasteViewModel` (like / dislike / haven't seen / undo, `hasEnoughLikes` ≥ 5) + tests
- [x] Bedøm-skærm → kortbunke (`TasteView`): én film ad gangen, knapper + swipe. Kendte, godt bedømte film fordelt på genrer
- [ ] Søgning efter egne favoritter (`OnDeviceMovieDataService.search` findes)
- [ ] Match-score og "why it matches"-søjler (fra `breakdown`) på anbefalingskortet
- [x] Anbefalings-skærm med loading, tom og fejl + faner
- [ ] Al tekst i UI og fejlbeskeder på engelsk
- [x] Tests for ViewModels og services – skal tilpasses likes

**Afklares med Anton:** antal film i appen (8.000?), `quality_boost` (0.02 eller 0), dislikes.

**Demo:** Vælg 5+ film på iPhone → tryk "Get recommendations" → anbefalinger fra Antons model vises med begrundelse, uden server.

---

## Sprint 2 – Filmdata
**Mål:** Appen kan vise en liste med ~40 film og serier fra en lokal JSON-fil.

**User stories**
1. *Som udvikler vil jeg have domænemodeller (Title, ContentTags, StreamingProvider, Availability …), så resten af appen har et fælles sprog.*
2. *Som bruger vil jeg se titler med år, genre og hvor de kan streames.* (midlertidig debugliste)

**Opgaver**
- [ ] Modeller i `Core/Models` (Codable, Hashable, Sendable)
- [ ] `mock_titles.json` (~40 titler, 5+ udbydere, tone/tempo/tema-tags)
- [ ] `MovieDataService` + `LocalJSONMovieDataService` + `MockMovieDataService`
- [ ] Tests: JSON kan læses, filtrering virker

**Demo:** Debugliste med titler efter login.

---

## Sprint 3 – Database og gem smagsdata
**Mål:** Et like, jeg giver i appen, bliver gemt i Supabase under min bruger.

**User stories**
1. *Som bruger vil jeg have, at mine valg gemmes sikkert, så kun jeg kan se dem.*
2. *Som bruger vil jeg kunne logge ind på en ny telefon og have mine data med.*

**Opgaver**
- [ ] SQL-migration: `profiles`, `taste_signals`, `preferences` med Row Level Security (godkendes før Swift-kode)
- [ ] `TasteSignalService` + `SupabaseTasteSignalService` + `MockTasteSignalService`
- [ ] Én lodret skive: like én film → række i `taste_signals`

**Demo:** Like en film → se rækken i Supabase Table Editor.

---

## Sprint 4 – Onboarding med favoritter
**Mål:** En ny bruger går gennem onboarding, vælger sine favoritter og ser "Your taste" til sidst.

**User stories**
1. *Som ny bruger vil jeg forstå, hvad CineMatch gør* (intro: "Pick movies you love – we'll find more like them").
2. *… vælge mindst 5 film, jeg kan lide, i et plakatgitter.*
3. *… søge efter mine egne favoritter i hele kataloget* (søgning i `movies`).
4. *… markere film som "not for me"*, så de aldrig bliver anbefalet (gemmes som `dislike`).
5. *… se en opsummering af min smag* (valgte film og genrer, der går igen). Kun visning, ingen beregning i appen.
6. *Som tilbagevendende bruger vil jeg ikke se onboarding igen.*
7. *(Senere)* vælge mine streamingtjenester.

**Opgaver**
- [ ] Alle UI-typer udsender `TasteSignal` (`.like` / `.dislike`)
- [ ] `OnboardingViewModel` (min. 5 likes, maks. 25) + tests
- [ ] Søgning: `MovieDataService.search(_:)` mod `movies` (`ilike` på `title`)
- [ ] Efter onboarding: kald `/recommend` og vis top 5
- [ ] Routing: logget ind uden likes → onboarding, med likes → hovedskærm

**Demo:** Ny bruger → intro → vælg favoritter → opsummering → top 5 fra Antons model.

---

## Sprint 5 – Anbefalinger med mock-ML
**Mål:** Hovedskærmen viser 5 anbefalingskort med begrundelse, før ML-servicen findes.

**Afhængighed:** `docs/ml_contract.md` skal skrives (tabeller, kolonner, endpoint, auth, fejl). Aftales med den, der laver ML-servicen.

**User stories**
1. *Som bruger vil jeg se 5 anbefalinger med titel, år, match-score og en begrundelse.*
2. *Som bruger vil jeg se en detaljeside med beskrivelse og hvorfor filmen matcher* (søjler fra `explanation`).
3. *Som bruger vil jeg se en tydelig besked, hvis anbefalingerne ikke er klar endnu.*

**Opgaver**
- [ ] `docs/ml_contract.md`
- [ ] `RecommendationService` + `MockRecommendationService`
- [ ] `Recommendation.explanation` (optional) + visning som søjler
- [ ] Bedste-udbyder-logik (testbar)
- [ ] Loading-, tom- og fejltilstande

**Demo:** Kort-liste + detaljevisning med mock-data.

---

## Sprint 6 – Rigtige anbefalinger + kontekst
**Mål:** Anbefalingerne kommer fra ML-servicen og ændrer sig med mit humør/tid.

**User stories**
1. *Som bruger vil jeg fortælle, hvad jeg har lyst til i dag (humør, tid, alene/sammen), og få nye forslag.*
2. *Som bruger vil jeg se, om en titel er i mine abonnementer.*
3. *Som bruger vil jeg give tommel op/ned på en anbefaling, så de næste bliver bedre* (`taste_signals` med `source = 'feedback'`).

**Opgaver**
- [ ] `RemoteRecommendationService` (læser tabel + kalder recompute-endpoint med access token)
- [ ] "What do you want to watch today?"-vælger
- [ ] Tommel op/ned → `taste_signals`
- [ ] Udvidelsespunkter (ikke bygget): "Surprise me", watchlist, allerede set

**Demo:** Skift kontekst eller giv feedback → nye anbefalinger fra ML-servicen.

---

## Sprint 7 – Profil og nulstilling
**Mål:** Jeg kan se og ændre min profil og starte forfra.

**User stories**
1. *… se mine kontooplysninger og mine valgte favoritter.*
2. *… ændre mine streamingtjenester.*
3. *… nulstille min smagsprofil uden at blive logget ud.*
4. *… logge ud og ind igen og have mine data.*

**Opgaver**
- [ ] `Features/Profile` + TabView (Today / Profile)
- [ ] Tests: nulstilling bevarer session, log ud/ind gendanner data

---

## Sprint 8 – Kvalitet
**Mål:** Koden er ryddelig, tilgængelig og dokumenteret.
- [ ] Arkitektur-review (MVVM-grænser, ingen service-kald fra views, ingen hemmeligheder)
- [ ] Dynamic Type og VoiceOver-labels
- [ ] `README.md`: arkitektur, Supabase-opsætning, kør med mocks
- [ ] Liste over teknisk gæld

---

## Product backlog (senere – prioriteres løbende)
- Rigtig filmdatabase (TMDB) og plakater via `tmdb_id`
- Dislikes trækker lignende film ned i modellen
- "Surprise me"
- Watchlist
- Skjul allerede sete titler
- Smagsstatistik-skærm
- Flere profiler pr. konto
- Notifikationer om nye matches
- Bruger retter algoritmens begrundelser
- Serier (MovieLens har kun film)
- Streamingudbydere via TMDB (`tmdbId` fra MovieLens `links.csv`)

## Risici og forhindringer
| Risiko | Konsekvens | Plan |
|---|---|---|
| Simulatoren er ustabil på Mac'en (8 GB RAM, crash) | Langsom test af UI | Test på rigtig iPhone. Luk andre apps, når Xcode kører |
| ML-servicen er ikke klar | Sprint 6 blokeret | Sprint 5 bruger mock, og kontrakten aftales tidligt |
| Supabase-skemaet ændres sent | Omskrivning af services | DTO'er mappes inde i services, så views/ViewModels ikke berøres |
| Modelfilen bliver for stor til appen | Lang opstart, stor app | Færre film (`--films`) eller naboer (`--neighbors`). Senere evt. binært format |
| Approksimation: kun 25 naboer pr. film gemmes | Lidt andre scorer end Antons model | Testet: samme rækkefølge. Flere naboer, hvis det bliver et problem |

## Retro-spørgsmål (efter hvert sprint)
1. Hvad gik godt?
2. Hvad drillede?
3. Hvad gør vi anderledes næste sprint?
