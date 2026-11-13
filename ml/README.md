# CineMatch – modellen i appen

Antons model (`Antons_Model.py`) kører **lokalt i appen**. Der er ingen ML-server.

Python regner på forhånd ud, hvilke film der ligner hinanden, og hvorfor. Resultatet gemmes i
`cinematch_model.json`, som ligger i appen. Appen (`Core/ML/OnDeviceRecommender.swift`) slår op i filen
og lægger scorerne sammen på samme måde som `Recommender.recommend()`.

## Lav en ny modelfil

1. Læg `export_for_app.py` i samme mappe som `Antons_Model.py` og `Letterboxd_Movies_Data/`.
2. Kør:
   ```bash
   pip install pandas numpy scipy scikit-learn joblib
   python export_for_app.py --model Antons_Model.py
   ```
   Første gang bygges Antons indeks også (det tager et stykke tid).
3. Kopiér `cinematch_model.json` til `CineMatch/Core/Resources/` i Xcode-projektet.
4. Byg appen. Findes filen, bruger appen modellen. Ellers bruger den falske anbefalinger.

## Indstillinger

| Flag | Standard | Betydning |
|---|---|---|
| `--films` | 8000 | Antal film i appen (de mest kendte, én pr. titel). Flere film = større fil |
| `--neighbors` | 25 | Lignende film gemt pr. film. Flere = mere præcis, større fil |
| `--starters` | 48 | Film i onboarding-gitteret, fordelt på genrer |
| `--chunk` | 500 | Film pr. beregningsblok. Sæt ned, hvis computeren løber tør for RAM |
| `--version` | dags dato | Modelversion, fx `2026-10-23-a` |

Filen fylder ca. 15–25 MB med standardindstillingerne.

## Hvad er anderledes end i Antons model?

- **Kun de valgte film** kan anbefales og søges frem (standard 8.000).
- **Popularitet bruges ikke** (`popularity_boost = 0`). Kvalitet (Letterboxd-rating) giver stadig et lille plus.
- En film, der ikke er blandt en likes 25 nærmeste naboer, tæller som 0 for den like.
  I test giver det samme rækkefølge som Antons model.
- **Film-id er Letterboxd `id`** fra Antons datasæt. Det bruges også, når likes gemmes i Supabase.
