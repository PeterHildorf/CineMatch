# CineMatch – Agil projektplan

> Levende dokument. Opdatér status efter hvert sprint.
> Prompts til hver fase ligger i `CineMatch_prompts.md`.

## Vision
CineMatch giver personlige, **forklarlige** film- og serieanbefalinger ud fra din smag, ikke ud fra hvad der er populært.
Appen er en *tynd klient*: den gemmer brugerens input i Supabase og viser de anbefalinger, ML-servicen skriver tilbage.

## Sådan arbejder vi
- **Sprints på ca. 1 uge** (2–4 lange sessioner à 1–2 timer).
- Hvert sprint har **ét mål** og ender med noget, der **virker og kan vises** (en "demo").
- **Lodrette skiver:** hellere en lille feature hele vejen igennem (UI → ViewModel → service → Supabase) end store lag, der først virker til sidst.
- **Læring først:** hvert sprint har en Swift-lektion i `Learning/`, som bruges direkte i sprintets kode.
- Efter hvert sprint: en kort **retro** (3 spørgsmål nederst) og opdatering af denne fil.

### Definition of Done (gælder alle user stories)
- [ ] Projektet bygger uden fejl
- [ ] Featuren er afprøvet på iPhone (rigtig enhed eller simulator)
- [ ] ViewModels og services har unit tests
- [ ] Ingen hemmeligheder i git (`Secrets.plist` er ignoreret)
- [ ] Committed i git med en beskrivende besked

---

## Status-overblik

| Sprint | Mål | Fase i prompts | Lektion | Status |
|---|---|---|---|---|
| 0 | Login-skelet med mock | Fase 2 (del) | 1–2: Funktioner, Optionals | ✅ Færdig (mangler commit) |
| 1 | Rigtigt login mod Supabase | Fase 2 | 3: Errors | 🔜 Næste |
| 2 | Filmdata i appen | Fase 1 | 4: Protokoller & DI | ⬜ |
| 3 | Database + gem smagsdata | Fase 3 (del 1) | 5: async/await | ⬜ |
| 4 | Onboarding-flow | Fase 3 (del 2) | 6: @Observable | ⬜ |
| 5 | Anbefalinger (med mock-ML) | Fase 4 (del 1) | – | ⬜ |
| 6 | Rigtige anbefalinger + kontekst | Fase 4 (del 2) | – | ⬜ |
| 7 | Profil, nulstilling, tabs | Fase 5 | – | ⬜ |
| 8 | Kvalitet & release-klar | Fase 6 | – | ⬜ |

---

## Sprint 0 – Login-skelet ✅
**Leveret:** `AuthService`-protokol, `SupabaseAuthService`, `MockAuthService`, `AuthViewModel`, `SignInView`, `AppContainer`, `RootView`, Supabase-pakken, tests skrevet.
**Rest:** test-targetet gik tabt i Xcode-crash, og arbejdet er ikke committed.

---

## Sprint 1 – Rigtigt login 🔜
**Mål:** Jeg kan logge ind med mit Apple-ID på min iPhone, og Supabase kender mig.

**User stories**
1. *Som bruger vil jeg logge ind med Apple, så jeg ikke skal huske endnu en adgangskode.*
   - Kriterier: Apple-arket vises → jeg lander på velkomstskærmen → brugeren findes i Supabase → Authentication → Users.
2. *Som bruger vil jeg forblive logget ind, når jeg lukker og åbner appen.*
   - Kriterier: genstart af appen springer login over. Uden internet bliver jeg ikke smidt ud.
3. *Som bruger vil jeg kunne logge ud.*
4. *Som udvikler vil jeg have kørende tests for login.* (genskab test-target)

**Opgaver**
- [ ] Commit sprint 0-arbejdet
- [ ] Supabase: slå Apple-provider til, indsæt Bundle ID under Client IDs
- [ ] Xcode: vælg Team, sæt eget Bundle ID (erstat `devplaceholder…`)
- [ ] Opret `App/Secrets.plist` ud fra `Secrets.example.plist`
- [ ] Kør på rigtig iPhone (simulatoren er ustabil på denne Mac)
- [ ] Genskab `CineMatchTests`-target og kør de 7 tests
- [ ] Lektion 3: Errors (`throws`, `try`, `do/catch`) → gennemgå `AuthViewModel.signIn`

**Demo:** Log ind på iPhone → luk app → åbn igen → stadig logget ind → log ud.

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
- [ ] Lektion 4: Protokoller & dependency injection

**Demo:** Debugliste med titler efter login.

---

## Sprint 3 – Database og gem smagsdata
**Mål:** En bedømmelse, jeg giver i appen, bliver gemt i Supabase under min bruger.

**User stories**
1. *Som bruger vil jeg have, at mine svar gemmes sikkert, så kun jeg kan se dem.*
2. *Som bruger vil jeg kunne logge ind på en ny telefon og have mine data med.*

**Opgaver**
- [ ] SQL-migration: `profiles`, `ratings`, `preferences` med Row Level Security (godkendes før Swift-kode)
- [ ] `TasteProfileStore` + `SupabaseTasteProfileStore` + `MockTasteProfileStore`
- [ ] Én lodret skive: bedøm én titel → række i `ratings`
- [ ] Lektion 5: async/await

**Demo:** Bedøm en film → se rækken i Supabase Table Editor.

---

## Sprint 4 – Onboarding
**Mål:** En ny bruger går gennem onboarding og ser "Din smagsprofil" til sidst.

**User stories**
1. *Som ny bruger vil jeg forstå, hvad CineMatch gør* (intro-skærme).
2. *… bedømme 12–15 titler.*
3. *… vælge genrer, tone, tempo, film vs. serier.*
4. *… vælge mine streamingtjenester.*
5. *… se en opsummering af min smag i almindeligt sprog.*
6. *Som tilbagevendende bruger vil jeg ikke se onboarding igen.*

**Opgaver**
- [ ] Alle UI-typer udsender `TasteSignal` (uafhængigt af UI-stil)
- [ ] `OnboardingViewModel` + tests
- [ ] Routing: logget ind uden data → onboarding, med data → hovedskærm
- [ ] Lektion 6: `@Observable` ViewModels

**Demo:** Ny bruger → onboarding → opsummering → data i Supabase.

---

## Sprint 5 – Anbefalinger med mock-ML
**Mål:** Hovedskærmen viser 5 anbefalingskort med begrundelse, før ML-servicen findes.

**Afhængighed:** `docs/ml_contract.md` skal skrives (tabeller, kolonner, endpoint, auth, fejl). Aftales med den, der laver ML-servicen.

**User stories**
1. *Som bruger vil jeg se 5 anbefalinger med titel, år, udbyder og en begrundelse.*
2. *Som bruger vil jeg se en detaljeside med beskrivelse og alle udbydere.*
3. *Som bruger vil jeg se en tydelig besked, hvis anbefalingerne ikke er klar endnu.*

**Opgaver**
- [ ] `docs/ml_contract.md`
- [ ] `RecommendationService` + `MockRecommendationService`
- [ ] `ReasonFormatter` (testbar) og bedste-udbyder-logik (testbar)
- [ ] Loading-, tom- og fejltilstande

**Demo:** Kort-liste + detaljevisning med mock-data.

---

## Sprint 6 – Rigtige anbefalinger + kontekst
**Mål:** Anbefalingerne kommer fra ML-servicen og ændrer sig med mit humør/tid.

**User stories**
1. *Som bruger vil jeg fortælle, hvad jeg har lyst til i dag (humør, tid, alene/sammen), og få nye forslag.*
2. *Som bruger vil jeg se, om en titel er i mine abonnementer.*

**Opgaver**
- [ ] `RemoteRecommendationService` (læser tabel + kalder recompute-endpoint med access token)
- [ ] "Hvad vil du se i dag?"-vælger
- [ ] Udvidelsespunkter (ikke bygget): tommel op/ned, "Overrask mig", watchlist, allerede set

**Demo:** Skift kontekst → nye anbefalinger fra ML-servicen.

---

## Sprint 7 – Profil og nulstilling
**Mål:** Jeg kan se og ændre min profil og starte forfra.

**User stories**
1. *… se mine kontooplysninger og en opsummering af min smag.*
2. *… ændre mine streamingtjenester.*
3. *… nulstille min smagsprofil uden at blive logget ud.*
4. *… logge ud og ind igen og have mine data.*

**Opgaver**
- [ ] `Features/Profile` + TabView (I dag / Profil)
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
- Rigtig filmdatabase (TMDB)
- Tommel op/ned-feedback
- "Overrask mig"
- Watchlist
- Skjul allerede sete titler
- Smagsstatistik-skærm
- Flere profiler pr. konto
- Notifikationer om nye matches
- Bruger retter algoritmens begrundelser
- Login med e-mail/adgangskode

## Risici og forhindringer
| Risiko | Konsekvens | Plan |
|---|---|---|
| Simulatoren er ustabil på Mac'en (8 GB RAM, crash) | Langsom test af UI | Test på rigtig iPhone. Luk andre apps, når Xcode kører |
| ML-servicen er ikke klar | Sprint 6 blokeret | Sprint 5 bruger mock, og kontrakten aftales tidligt |
| Supabase-skemaet ændres sent | Omskrivning af services | DTO'er mappes inde i services, så views/ViewModels ikke berøres |

## Retro-spørgsmål (efter hvert sprint)
1. Hvad gik godt?
2. Hvad drillede?
3. Hvad gør vi anderledes næste sprint?
