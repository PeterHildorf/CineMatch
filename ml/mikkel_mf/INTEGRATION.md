# CineMatch matrix-factorization export: integration guide

This package contains the current trained matrix-factorization model for local
inference. It requires a new Swift loader and scoring routine. It is not a
replacement file for Anton's neighbour-based `cinematch_model.json`.

## Package contents

- `cinematch_mf.json`: learned movie parameters and the exported catalogue.
- `export_report.json`: source information, counts and excluded ID mappings.
- `reference_cases.json`: sample inputs and expected recommendations from Python.
- `INTEGRATION.md`: this guide.

No training ratings, training-user identities or trained user profiles are
included. No Python, PyTorch, ML server or retraining is needed on the phone.

## Load the model

Decode numbers used in inference as Swift `Double`. Require all of:

```text
format        = "cinematch.matrix-factorization"
schemaVersion = 1
modelType     = "explicit_rating_matrix_factorization"
```

This format deliberately has no `formatVersion` field. Anton's app format has a
different contract; its version number must not be used to select this loader.

The root fields are:

| Field | Meaning |
| --- | --- |
| `modelVersion` | `mf-` followed by the first 12 characters of the checkpoint SHA-256 |
| `factorCount` | Number of learned dimensions, called `d` below |
| `globalMean` | Global rating intercept, `mu` |
| `foldInRegularization` | Positive penalty for the new user's factor vector |
| `biasRegularization` | Positive penalty for the new user's intercept |
| `ratingScale` | `min: 0.5`, `max: 5`, `step: 0.5` |
| `scoreType` | `"raw_ranking_score"` |
| `tieBreak` | `"catalogue_order"` |
| `movieOnlyVerified` | `false`: content types have not been verified |
| `tmdbIdentityVerified` | `false`: mappings have not been checked against TMDB |
| `movies` | Ordered catalogue and parameters |

Each `movies` entry contains `tmdbId`, `movieLensId`, `title`, `genres` (an array),
`bias` and `factors` (exactly `d` numbers). Preserve array order and build a
`tmdbId -> array index` lookup. Use TMDB IDs at the app boundary; MovieLens IDs
are included for traceability, not as app identities. Genres are display
metadata, not model inputs.

Reject unsupported schema/model types, nonfinite parameters, nonpositive
regularization, wrong factor lengths, and invalid or duplicate TMDB IDs when
loading. The supplied export retains the trained numeric values without
decimal truncation.

## Inputs

Accept one current rating per film:

```json
{
  "ratings": [{"tmdbId": 862, "rating": 4.5}],
  "excludeTmdbIds": [],
  "k": 50
}
```

The ID above is illustrative; use the supplied reference cases for a guaranteed
supported input. Ratings must be finite half-stars from 0.5 through 5. Reject
duplicate rated IDs and report rated IDs absent from this export. Ignore unknown
IDs in `excludeTmdbIds`. Require a positive integer `k`.

This model uses real star ratings. It has no validated conversion from
likes/dislikes to stars. "Haven't seen" supplies no rating. Streaming choices,
mood and Family are not inputs to the current model.

## Calculate recommendations locally

For movie `i`, let `b_i = movies[i].bias` and `q_i = movies[i].factors`.
The baseline is `base_i = mu + b_i`.

For each supplied rating `r_j` of movie `i_j`, create:

```text
x_j = [1, q_i_j[0], ..., q_i_j[d-1]]
y_j = r_j - base_i_j
```

Fit the new user's intercept and vector by solving:

```text
A = diag(biasRegularization, foldInRegularization, ..., foldInRegularization)
z = zeros(d + 1)

for each rating j:
    A += outer(x_j, x_j)
    z += x_j * y_j

solve A * coefficients = z
userBias = coefficients[0]
userFactors = coefficients[1...d]

score_i = base_i + userBias + dot(q_i, userFactors)
```

Use a linear-system solver rather than explicitly computing an inverse. With
16 factors this is a 17-by-17 system. The loss uses a **sum** of rating errors;
do not divide `A` or `z` by the number of ratings. Movie parameters remain fixed.

Remove all rated films and all known `excludeTmdbIds` from the candidates.
Sort remaining films by descending full-precision score, breaking exact ties
by their original array position. Return at most `k`, or fewer if the catalogue
is exhausted. Round scores only after sorting; the Python fixtures use six
decimal places. The complete exported catalogue is scored, so top 50 does not
depend on a fixed number of film neighbours.

For zero ratings, Python returns `base_i` and `personalized: false`. This case
is included for numerical parity. In the product, require at least one supported
rating before presenting personal recommendations; the zero-rating prior is
not personal taste. The model also contains a shared movie bias when ratings
are present, so it should not be described as a pure taste-only score.

## Verify the Swift implementation

Read `reference_cases.json`, requiring its
`format: "cinematch.mf-reference-cases"`, `schemaVersion: 1` and matching
`modelVersion`. Also verify that its `modelJsonSha256` equals the SHA-256 of the
exact `cinematch_mf.json` bytes. The same checkpoint can be exported with updated
ID mappings, so `modelVersion` alone does not identify the complete export.
For every case:

1. Run the case's `input.ratings`, `input.excludeTmdbIds` and `input.k`.
2. Compare the ordered returned TMDB IDs with
   `expected.recommendations[*].tmdbId`.
3. Compare each score with the expected score within `scoreTolerance` (`1e-6`).
4. Check `personalized` and `ratingsUsed` against their expected values.

Use `Double` throughout and never rank rounded scores. Keep these fixtures as
regression tests when changing the Swift implementation or updating the model.
There is no supplied Swift implementation in this package.

## Catalogue scope and current limitations

The exporter excludes every row with a missing/invalid TMDB mapping and every
row in a duplicate-TMDB group. It does not arbitrarily choose or merge learned
vectors. See `export_report.json` for the actual counts and identities. This
restricts available inputs and candidates; the retained trained parameters
remain unchanged. Reference results use the same restrictions.

A positive TMDB ID does not establish correct identity or that a record is a
movie. This is an integration/testing export, not a verified movie-only release.
Validate identities, remove TV/miniseries and verify onboarding films before
shipping a movie-only app.

Scores are unclipped ranking values. They are neither 0–1 match percentages nor
guaranteed displayed star predictions. This model supplies no "because" film,
feature breakdown, mood weights, thematic tags or age classifications. Do not
invent those explanations from its latent factors. Posters and streaming
availability can still be fetched by the app using TMDB IDs.
