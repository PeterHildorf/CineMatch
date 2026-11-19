# Conditional neighbour model integration

The app uses the selected `cm-20261119-full-knn-conditional` model locally. Its frozen graph has 9,021 MovieLens nodes and 902,100 directed edges. A separate eligibility flag limits app-facing inputs and outputs to verified, uniquely mapped TMDB movies. Removing a movie from the app catalogue does not remove its internal graph position or change the learned weights.

The completed 19 November 2026 verification supports **8,937 movies**, all verified by IMDb agreement. Exclusions are 61 unavailable TMDB movie records, 15 conflicting IMDb mappings, one record without confirming IMDb evidence, three missing links and four rows in duplicate-TMDB groups. There are no unresolved network failures in the exported report. The conservative legacy bridge contains 3,789 Letterboxd-to-TMDB mappings. The JSON bundle is approximately 23 MB; its exact size and checksum are in `manifest.json`. Load time and runtime memory are separate measurements.

## Verification and export

Run these from the sibling ML repository, `CineMatch`, using its existing environment:

```sh
.venv/bin/python experiments/verify_tmdb_catalogue.py
.venv/bin/python experiments/export_conditional_ios.py
```

The verifier reads `TMDB_READ_ACCESS_TOKEN` or `TMDB_API_KEY` from the environment, or `TMDB_READ_ACCESS_TOKEN` from the frontend's ignored `CineMatch/App/Secrets.plist`. Credentials are never copied into outputs. The API response cache is resumable and expires after seven days by default. Authentication failures stop the run. Temporary network/server/rate-limit failures remain unresolved and block export; they are not classified as missing films.

Before live requests, the verifier excludes the three model rows without TMDB links and all four rows in two duplicate-TMDB groups. For the other 9,014 rows it requests the TMDB movie endpoint, including alternative titles. Production eligibility requires matching IMDb identifiers. Conflicting or missing IMDb identifiers are excluded even if titles happen to match. Title/year agreement is retained as review evidence, but does not establish that editions or media identity are equivalent. This conservative rule excludes the one title/year-only record instead of silently accepting it. Missing or uncertain records are excluded and reported. TMDB movie availability does not imply availability on a Danish streaming provider.

The current policy is `tmdb-movie-matching-imdb-v2`. Fresh cached API responses can be reclassified without new requests or credentials using `verify_tmdb_catalogue.py --cached-only`. Expired, incomplete or failed cached responses cannot produce an exportable report.

The exporter requires a complete verification report, matching source checksums, recent timestamps for every API-derived decision, unique eligible TMDB IDs and classifications consistent with retained response evidence. The report and cache live under the ML repository's `experiments/integration/`; no unverified production model is emitted. The final counts and hashes are recorded in the generated `manifest.json` beside this document.

## Bundle contract

`CineMatch/Core/Resources/cinematch_knn.json` contains:

| Field | Meaning |
| --- | --- |
| `format`, `schemaVersion`, `modelType` | `cinematch.conditional-neighbors`, `1`, `positive_conditional_neighbors` |
| `modelVersion` | Frozen training-run identity plus a checksum of the exported catalogue and legacy bridge |
| `sourceModelSHA256` | Exact original NPZ checksum |
| `tmdbVerificationSHA256`, `catalogueSHA256` | Provenance of verification and app-facing identities |
| `tmdbIdentityVerified` | Required `true` for this production format |
| `movies` | All original model positions, with MovieLens ID, nullable TMDB ID, eligibility, display title/year/genres and training rating count |
| `neighborOffsets` | Row boundaries, length `movies.count + 1` |
| `neighborIndices`, `neighborWeights` | Directed target positions and exact stored weights |
| `legacyMappings` | Verified conservative Letterboxd-to-TMDB bridge; unresolved entries are not present |
| `scoring` | Explicit positive aggregation, rating centre 3, training-count fallback and original-order ties |

Only eligible rows may be used as public TMDB inputs or returned as app recommendations. The scorer still allocates the full catalogue score vector and preserves all graph indices. Search and onboarding must use this same eligible catalogue, never the previous Anton bundle or an unrestricted TMDB search result list.

## Scoring

For every recognised rating, add `max(rating - 3, 0) × stored edge weight` to each target score. Great contributes 1 and Fantastic contributes 2. Dislikes and neutral ratings contribute zero; every seen/rated movie is excluded from output. “Haven't seen” is not passed as a rating and does not exclude a recommendation.

If the entire score vector is zero, replace it with training rating counts before watched exclusions. Apply eligibility and watched filters, then sort by descending score and original graph position for ties. Do not cap input at 25, add a quality/popularity bonus, symmetrise the graph, deduplicate by title, or normalize its rows. Scores are ranking values, not percentages.

The exported weights preserve the exact Float32 values stored in Python, represented as JSON numbers and read into Swift Double. Accumulation is Double in both implementations and retains input order.

## Existing opinions

The generated bridge accepts only unambiguous existing exact-title/year mappings or new unique normalized-title/year candidates, followed by confirmation against the verified TMDB record's title or official alternative title and release year. It does not automatically accept year-offset/fuzzy mappings. Multiple legacy opinions mapping to one public movie require deterministic newest-opinion handling in the app; original records remain recoverable. `experiments/integration/legacy_mapping_verified.json` records both accepted and unresolved cases and source checksums.

## Verification fixtures

`reference_cases.json` is generated from synthetic profiles over the actual production graph, using the unchanged Python scorer. No validation or final-holdout profiles are read. It records the production bundle checksum, ordered TMDB results, raw scores, usable input counts and fallback state. A copy at `CineMatchTests/knn_reference_cases.json` is included in the Xcode test bundle.

`synthetic_model.json` and `synthetic_cases.json` are explicitly test-only artifacts covering directed weights, tied and zero scores, fractional ratings, an ineligible high-score node, watched exclusions, unknown inputs and fallback. They are outside the app resource folder and must never replace the production bundle. They can be regenerated without credentials using:

```sh
.venv/bin/python experiments/export_conditional_ios.py --synthetic-only
.venv/bin/python -m pytest tests/test_conditional_ios_export.py
```

The frozen holdout result describes the original full catalogue. These eligibility rules and the app's self-selected onboarding change serving conditions; they do not inherit a measured app uplift from that result.

## Implementation validation

On 19 November 2026, the final IMDb-verified export passed all 73 Python repository tests and 34 Swift checks, including eight production Python/Swift reference profiles. The Swift checks compile the actual model, catalogue and opinion services, recommendation view model and remote adapters against the project's pinned Supabase 2.55.3 dependency. They cover watched exclusions, unknown/ineligible inputs, full-catalogue Search, onboarding counts, legacy verdicts and timestamps, daily-pick progress, cache refresh and account isolation.

From the frontend repository, run `python3 ml/conditional_knn/check_swift.py --with-supabase`. The temporary test package copies only listed source files and public model/test resources, never `Secrets.plist`. `--unit-only` runs synthetic checks without requiring a production bundle. The runner accommodates the installed Command Line Tools testing-framework layout.

The read-only backend schema check requested zero rows and confirmed the expected opinion, batch, feedback and neutral/great metrics columns. It did not create a user, change data, validate authenticated writes or inspect SQL constraints. No bulk user-data migration was run: verified old opinions are translated on read, and new opinions use the existing TMDB namespace.

Full iOS/SwiftUI build, simulator/device rendering and device performance remain unverified because Xcode is not installed in this environment. Source syntax checks passed for the changed app wiring and Search view. The machine-readable results are in [validation.json](validation.json).
