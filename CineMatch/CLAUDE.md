# CineMatch – Project Guide for Claude

CineMatch is an iOS app (SwiftUI) that gives personalized, *explainable* movie & TV
recommendations based on an individual taste profile rather than general popularity.

This file contains the permanent rules for the project. Follow them in every task.

## Tech stack
- Swift + SwiftUI, iOS 17+ deployment target
- Swift Concurrency (async/await) for all service calls
- Observation framework (`@Observable`) for ViewModels
- SwiftData (or UserDefaults where trivial) for local persistence
- Keychain for auth credentials / user identifier
- XCTest or Swift Testing for unit tests

## Architecture: MVVM + protocol-based services
- **Views** only render state and forward user intent. No business logic, no persistence, no direct service calls.
- **ViewModels** (`@Observable`, `@MainActor`) own screen state and call services through **protocols only**.
- **Models** are plain `Codable`, `Hashable`, `Sendable` value types (structs/enums).
- **Services** are defined as protocols. Concrete implementations (Mock/Local now, API/ML later) are injected.
- All dependencies are created in one place (`AppContainer`) and injected. No singletons accessed directly from views or view models.
- Swapping an implementation (e.g. `LocalJSONMovieDataService` → `TMDBMovieDataService`) must require **zero changes** to Views or ViewModels.

### Core service protocols
- `MovieDataService` – fetch titles (all, by id, by filters). MVP: `LocalJSONMovieDataService` reading a bundled JSON file.
- `RecommendationService` – `recommendations(for profile:, context:, count:) async throws -> [Recommendation]`. MVP: simple content-based scoring. Later: real content-based → collaborative filtering.
- `StreamingAvailabilityService` – where a title can be watched + best-fit provider for a user's subscriptions.
- `AuthService` – sign in / sign out / current session. MVP: Sign in with Apple. Must allow adding other providers (e.g. email/password) later.
- `TasteProfileStore` – load / save / reset the taste profile and user preferences for a given user ID. MVP: local (SwiftData). Later: backend.

## Folder structure
```
CineMatch/
├── App/                     # CineMatchApp, AppContainer (DI), RootView (routing)
├── Core/
│   ├── Models/              # Title, Genre, ContentTags, StreamingProvider, TasteProfile,
│   │                        # Recommendation, ViewingContext, UserSession, ...
│   ├── Services/
│   │   ├── Protocols/       # All service protocols
│   │   ├── Local/           # MVP implementations (JSON, SwiftData, heuristic recs)
│   │   └── Mock/            # Test/preview doubles
│   ├── Persistence/         # SwiftData models + mapping to domain models, Keychain helper
│   ├── Resources/           # mock_titles.json
│   └── Shared/              # Reusable UI components, extensions
├── Features/
│   ├── Auth/                # Views/, ViewModels/
│   ├── Onboarding/          # Views/, ViewModels/
│   ├── Recommendations/     # Views/, ViewModels/
│   └── Profile/             # Views/, ViewModels/
└── CineMatchTests/
```
New features go in their own folder under `Features/`.

## Data model principles
- Domain models are separate from persistence models (SwiftData `@Model` classes) and from future API DTOs. Map between them in the service layer.
- `Title` supports both movies and TV shows (`kind: .movie | .tvShow`) and has: id, title, kind, year, genres, overview, posterURL, runtime/seasons, tags (tone, pace, themes), availability.
- `StreamingProvider` must be extensible (not a closed enum of 3 services) so more providers can be added via data.
- `TasteProfile` stores **signals** (e.g. rated titles, genre/tag weights), independent of *how* they were collected (rating list today, swipe gestures later).
- Taste data is always keyed by the authenticated user ID.
- Use stable string IDs so a real movie database can be swapped in later.

## Backlog (do NOT build yet, but do not block)
Real movie database (TMDB) · thumbs up/down feedback loop · "Surprise me" · watchlist ·
"already watched" exclusion · taste statistics screen · multiple profiles per account ·
notifications for new matches · user corrections of the algorithm's reasoning.

When designing models and protocols, check that none of these would require restructuring.

## Working agreement
- Work in the phase I ask for. Do not jump ahead to later phases.
- **Ask before** making decisions that are costly to change later (data model shape, persistence choice, how auth ties to storage, protocol signatures). Present options with trade-offs.
- List any assumptions you make at the end of each answer.
- Keep the project compiling after every phase. Add SwiftUI `#Preview`s using mock services.
- Write unit tests for services and view models (not views).
- Do NOT integrate any external movie API yet.
- Prefer small, readable files over large ones.
