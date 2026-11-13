# CineMatch – Trinvise prompts til Claude-agenten i Xcode

**Sådan bruger du dem:** `CLAUDE.md` skal ligge i projektets rodmappe, så agenten kender reglerne.
Indsæt én prompt ad gangen. Byg og kør appen (⌘R), og commit i git, før du går videre.

**Vigtigt:** Appen laver ikke anbefalinger. Den gemmer brugerens data i Supabase og viser
de anbefalinger, ML-servicen har skrevet tilbage. Fase 4 kræver, at `docs/ml_contract.md` findes.

> **Hvem skriver koden (fra 23/10):** Claude skriver koden. Jeg (Peter) reviewer, tester og godkender.
> Tilføj gerne denne linje nederst i hver prompt:
> *"Write the code with short Danish comments explaining the non-obvious parts."*
>
> **Ændringer siden prompts blev skrevet:**
> - Login er e-mail + adgangskode i Supabase, ikke Sign in with Apple (Fase 2 er færdig).
> - Filmdata kommer fra MovieLens (`ml-latest-small`). ID'er er MovieLens `movieId` (Int), ikke TMDB-strenge. Kun film, ingen serier endnu.
> - Arkitektur "variant A": ML-servicen er Python FastAPI med `POST /recommend`, og den skriver top 5 til `recommendations`.
> - **(23/10) Al tekst i appen er på engelsk.**
> - **(23/10) Modellen er Antons content-based model.** Den tager en liste af film, brugeren kan lide. Onboarding bruger derfor **likes** ("Pick movies you love") i stedet for 1–5 stjerner, og `taste_signals` (`like` / `dislike`) erstatter `ratings`. Se `docs/ml_contract.md`.

---

## Fase 0 – Plan og afklaring (ingen kode)

```
Read CLAUDE.md (and docs/ml_contract.md if it exists). We are starting the CineMatch MVP.

Remember: the app is a thin client. It does NOT compute recommendations.
It stores user input in Supabase and displays recommendations written by the ML service.

Do NOT write any code yet. Instead:
1. Propose the concrete file list for the iOS folder structure in CLAUDE.md.
2. Propose the domain models (Title, ContentTags, StreamingProvider, Availability, Rating,
   TasteSignal, ViewingContext, Recommendation, RecommendationReason, UserSession)
   as Swift type sketches.
3. Propose the signatures of all service protocols (MovieDataService, RecommendationService,
   StreamingAvailabilityService, AuthService, TasteProfileStore).
   RecommendationService must cover: reading today's recommendations for a context,
   and requesting a recompute from the ML service.
4. Explain how the Supabase auth user id ties the app's data to the ML service.
5. Explain how onboarding signals stay independent of the UI style (ratings, swipes,
   This-or-That, sliders all emit the same signal types).
6. Check each backlog item in CLAUDE.md against the design and note what hook exists for it.
7. List what docs/ml_contract.md must contain for the app side to work
   (tables, columns, endpoint, auth, error cases).

End with a list of open decisions I need to make, each with 2–3 options and trade-offs.
```

---

## Fase 1 – Core-modeller og filmdata

```
Phase 1: Core models and movie data. Use the decisions we agreed on in Phase 0.

Build:
- All domain models in Core/Models (Codable, Hashable, Sendable).
- MovieDataService protocol + LocalJSONMovieDataService reading Core/Resources/mock_titles.json.
- mock_titles.json with ~40 varied titles (movies and TV shows, many genres, tone/pace/theme tags,
  availability across at least 5 providers: Netflix, Prime Video, Disney+, HBO Max, Apple TV+).
  Use TMDB-style string IDs. Placeholder posters or SF Symbols, no copyrighted images.
- A data-driven StreamingProvider catalog, so adding a provider needs no code changes.
- AppContainer that creates and injects services.
- MockMovieDataService for previews/tests.
- Unit tests: JSON decodes, filtering works.

No Supabase yet. No UI beyond a temporary debug list of the loaded titles.
Confirm the project builds.
```

---

## Fase 2 – Login (Sign in with Apple → Supabase) — ✅ færdig, men bygget med e-mail + adgangskode

```
Phase 2: Authentication.

Build:
- Add the supabase-swift package (Swift Package Manager).
- A config file for Supabase URL + anon key, excluded from git, with an example file that IS committed.
  The Supabase client is created in AppContainer only.
- AuthService protocol + SupabaseAuthService: Sign in with Apple, then exchange the
  Apple ID token for a Supabase session (signInWithIdToken, with nonce).
- Restore the session on launch; sign out cleanly if it is invalid.
- UserSession model exposing the Supabase user id as the stable userID.
- Features/Auth: SignInView + AuthViewModel.
- RootView routing: signed out → SignInView; signed in → placeholder main content.
- MockAuthService so I can run in the Simulator without a real Apple ID or Supabase.
- Unit tests for AuthViewModel using MockAuthService.

Tell me exactly which manual steps I must do in Xcode (Signing & Capabilities → Sign in with Apple)
and in the Supabase dashboard (enable the Apple provider, etc.).
Design AuthService so email/password could be added later without touching other features.
```

---

## Fase 3 – Onboarding og lagring i Supabase

> **(23/10)** Trin 2 er nu "pick favorites" (likes) i stedet for at bedømme titler, og tabellen hedder `taste_signals` i stedet for `ratings`. Se `docs/ml_contract.md`.

```
Phase 3: Onboarding and saving user data to Supabase.

First, propose the SQL for the tables profiles, taste_signals and preferences (with Row Level Security:
users only read/write their own rows) as a file for supabase/migrations/.
Wait for my approval before writing any Swift code that depends on the schema.

Then build:
- TasteSignalService protocol + SupabaseTasteSignalService (DTOs mapped to domain models
  inside the service) + MockTasteSignalService.
- Features/Onboarding:
  1. Intro screens explaining what CineMatch does ("Pick movies you love – we'll find more like them").
  2. Pick favorites: a poster grid where the user taps movies they love (min 5, max 25),
     plus a search field over the movies table. Optional "Not for me" marks a dislike.
  3. Summary screen: "Your taste" showing the picked movies and recurring genres (display only).
  4. (Later) Choose streaming subscriptions.
- All onboarding UIs emit TasteSignal values (.like / .dislike); OnboardingViewModel collects them and saves
  them through TasteSignalService. No scoring or ML logic in the app.
- All UI text in English.
- RootView routing: signed in without likes → Onboarding; with likes → main view.
- Unit tests for OnboardingViewModel with MockTasteSignalService.
```

---

## Fase 4 – Visning af anbefalinger fra ML-servicen

```
Phase 4: Displaying recommendations.

Read docs/ml_contract.md first. If it is missing or unclear, STOP and list what is missing
instead of guessing table columns or endpoints.

Build:
- RecommendationService implementations:
  - MockRecommendationService: fixed fake results so the UI works before the ML service exists.
  - RemoteRecommendationService: reads the recommendations table in Supabase and calls
    the ML service's recompute endpoint with the user's Supabase access token.
- After onboarding is saved: request a recompute, then show the result.
- Features/Recommendations:
  - "What do you want to see today?" context picker (mood, time available, movie vs. show,
    alone/with others). Saving a new context triggers a recompute.
  - List of 5 cards: poster placeholder, title, year, match score, reason, best provider badge.
  - Detail view with overview, "why it matches" bars (from explanation) and all providers.
  - Clear loading, empty ("your recommendations are being prepared") and error states,
    because the ML service can be slow or offline.
- The ML service delivers reason as finished English text. Show it as-is.
- StreamingAvailabilityService: best-fit provider based on the user's subscriptions
  (subscribed first; otherwise show where it's available and mark "not in your subscriptions").
- Leave extension points (not implemented) for: thumbs up/down feedback (taste_signals with
  source = 'feedback'), "Surprise me", watchlist, already-watched exclusion.
- Unit tests for best-provider selection and the RecommendationsViewModel
  (with MockRecommendationService, including error and empty states).

Do NOT implement any scoring or recommendation logic in the app.
```

---

## Fase 5 – Profil, abonnementer og nulstilling

```
Phase 5: Profile and reset.

Build Features/Profile:
- Account info (from UserSession) and the user's picked favorites.
- Edit streaming subscriptions (saved to Supabase).
- "Reset taste profile": confirmation dialog, then delete this user's taste_signals, preferences,
  contexts and recommendations in Supabase – NOT the auth session. Route back to onboarding.
- Sign out (data stays in Supabase, so signing back in restores it).
- TabView: Today (recommendations) + Profile.
- Unit tests with mocks: reset removes taste data but keeps the session;
  sign-out/sign-in restores data.
```

---

## Fase 6 – Review og oprydning

```
Phase 6: Review.

1. Review the iOS codebase against CLAUDE.md: MVVM boundaries, no service calls from views,
   all dependencies injected via protocols, no recommendation logic in the app,
   no secrets in the app.
2. Check that every Supabase table and endpoint the app uses matches docs/ml_contract.md.
3. For each backlog item, describe in 2–3 lines where it would plug in.
4. List technical debt, missing tests and accessibility issues (Dynamic Type, VoiceOver labels).
5. Write a short ios/README.md: architecture overview, how to configure Supabase,
   and how to run the app with mock services.

Fix only small issues directly; list bigger ones for me to decide on.
```
