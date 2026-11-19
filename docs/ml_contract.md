# CineMatch app and model contract

Updated 19 November 2026. The active app uses the selected conditional-neighbour model locally. Swipe, Search, onboarding and Today share one verified TMDB catalogue. There is no recommendation server or `/recommend` endpoint in this flow.

## Model and catalogue

The source is `cm-20261119-full-knn-conditional`, trained on the fixed 9,021-movie MovieLens catalogue. `CineMatch/Core/Resources/cinematch_knn.json` contains the frozen graph, training counts, original graph positions and a separate eligibility flag for each movie. See `ml/conditional_knn/INTEGRATION.md` and its export manifest for the current supported count and checksums.

Only movies with verified TMDB movie identities and unambiguous mappings are eligible. Missing, duplicate, unavailable, mismatched and uncertain mappings are excluded from the app catalogue. Temporary network failures prevent export rather than being classified as missing films.

All active public movie IDs are TMDB IDs. The model retains MovieLens IDs and graph positions internally. The catalogue supplies the conversion. Removing an app-visible film never renumbers the frozen graph.

`ConditionalNeighborMovieDataService` supplies the same eligible set to onboarding/Swipe, full-catalogue Search and recommendation title lookup. The scorer checks membership again and filters outputs before taking the requested number of results. A raw TMDB search result cannot become model input without catalogue membership.

## Numeric opinions

| Button | Stored rating | Model weight | Excluded as watched |
| --- | ---: | ---: | --- |
| Haven't seen | 0 | Not a rating | No |
| Horrible | 1 | 0 | Yes |
| Bad | 2 | 0 | Yes |
| Neutral | 3 | 0 | Yes |
| Great | 4 | 1 | Yes |
| Fantastic | 5 | 2 | Yes |

The app requires five supported Great/Fantastic opinions before showing personalised results. The scorer itself supports sparse inputs and popularity fallback. Every supported seen opinion is passed with its numeric value; there is no 25-like cap. For legacy records, `rating=3` with `signal=like` means old Great, while `rating=3` with `signal=neutral` stays Neutral.

## Ranking

For each candidate, sum `max(rating - 3, 0) * stored directed neighbour weight` over the accepted ratings. Keep zero-score candidates. If the complete original score vector is zero, use training rating counts before applying watched and eligibility filters. Sort by descending score and break ties by original graph position.

Do not add quality bonuses, symmetrical negative weights, title deduplication or extra popularity blends. Those would change the selected model. Scores are raw ranking values, not percentages or predicted star ratings. The English explanation is “Based on your ratings.”

The service returns 50 eligible unseen candidates. Existing streaming filtering and daily-pick promotion can change what is displayed; logs preserve both model rank and displayed position. More candidates can be requested without changing model weights. A movie existing in TMDB does not establish Danish streaming availability.

## Storage and legacy opinions

Supabase remains responsible for authentication, opinions, preferences and events. New opinions/events use the existing `stars` pipeline because that namespace already stores TMDB IDs. Its name is historical; the batch `model_version` identifies the active model. This avoids changing database pipeline constraints or reinterpreting old `swipe` integers as TMDB IDs.

`SupportedCatalogueTasteSignalService` reads canonical TMDB opinions and verified translations of legacy `swipe` and `search` Letterboxd opinions. It keeps the newest opinion per supported movie, with canonical priority on tied timestamps. Reads never copy, overwrite or delete original records. Unmapped and unsupported opinions remain recoverable in their original stores but do not count toward onboarding.

New answers write to canonical storage only. Explicit removal deletes corresponding verified legacy answers too, so undo cannot reveal an older answer again. Profile’s explicit Start fresh clears canonical and both legacy stores. These destructive actions occur only when the user invokes them.

The new daily-pick key is `dailyPick.tmdb.knn.v1.<user>`. First use preserves answered-day/streak history from `dailyPick.swipe.<user>` but does not copy Letterboxd movie IDs. A migration marker prevents old progress from reappearing after reset.

## Session and telemetry

Recommendation caches clear across sign-out. In-flight computations are invalidated before they can publish stale results. Screen state is keyed by user ID. Queued telemetry captures its originating user and drops events after an account change; explicit payload `user_id` also allows RLS to reject an in-flight session mismatch.

Batches record the model/catalogue version and accepted input count. Impressions record TMDB ID, raw score, model rank and shown position. Feedback retains the numeric verdict. Keep historical events in their original namespace and model version.

The existing 0006 schema supports the current verdict scale. The read-only schema check confirms the rating/event columns and neutral/great metrics view are exposed; it does not perform authenticated writes or inspect SQL constraints. Do not blindly rerun 0006, because its historical score conversion is not safe to repeat after real Neutral feedback exists.

## Failure behaviour and checks

A missing, invalid or unverified conditional-model bundle produces an unavailable/error state. It does not silently select Anton, MF or mock recommendations. Mock data remains available through explicit demo/previews.

Credentials stay in ignored `CineMatch/App/Secrets.plist`; no credentials belong in model exports, reports or source control. A model export includes the source checksum, verification evidence and reference rankings. Python/Swift parity, eligibility, exclusions, legacy translation and session invalidation are checked before delivery. Use `python3 ml/conditional_knn/check_swift.py` for portable Swift checks and the Xcode test target for full iOS/Supabase integration.
