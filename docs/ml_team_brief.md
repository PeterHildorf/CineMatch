# CineMatch – hvad appen har brug for fra ML-teamet

> Til ML-teamet. Kan læses direkte eller gives som prompt til jeres AI-assistent.
> Fuld kontrakt: `docs/ml_contract.md` · SQL: `supabase/migrations/`
> Opdateret 23/10: **appen er på engelsk**, så `reason` og fejlbeskeder skal være på engelsk.
> Opdateret 23/10: **onboarding giver nu likes i stedet for 1–5 stjerner.** Input er tabellen `taste_signals`, så det passer direkte til `Recommender.recommend(liked_ids)`.

---

## Prompt

Du hjælper ML-teamet på CineMatch, en iOS-app der giver personlige filmanbefalinger.
Appen (SwiftUI) og ML-servicen (Python FastAPI) taler **aldrig direkte om data**. De mødes i en
Supabase-database (PostgreSQL). Appen laver ingen ML. Den gemmer de film, brugeren kan lide, og viser
de anbefalinger, ML-servicen skriver tilbage. Al tekst i appen er på engelsk.

Modellen er Antons content-based `Recommender` (`Antons_Model.py`). Den tager en liste af film, brugeren
kan lide, og returnerer lignende film med forklaring (`because`, `shared`, `breakdown`).
**Den skal ikke skrives om.** Der skal bygges en `service.py` (FastAPI) ovenpå, der importerer den.

### Flowet

1. Brugeren vælger mindst 5 film, han kan lide, i onboarding (plakatgitter + søgning) → rækker i `taste_signals` med `signal = 'like'`.
   Han kan også markere film som "not for me" → `signal = 'dislike'`.
2. Appen kalder `POST /recommend` med brugerens Supabase access token.
3. ML-servicen verificerer tokenet og læser brugerens `taste_signals`.
4. `liked` = film med `signal = 'like'` (højst 25, nyeste først) → `recommender.recommend(liked, limit=30)`.
5. ML-servicen fjerner alle film, brugeren har markeret (like og dislike), tager top 5 og skriver dem til `recommendations`.
6. Appen læser `recommendations` og viser dem.

### Datasættet og ID'er

Vi bruger `merged_datasets.csv` (MovieLens + Letterboxd, 71.828 film, én række pr. film).
**`movieId` (MovieLens) er det fælles film-ID** i hele systemet: i appen og i alle tabeller.

**Antons model bruger Letterboxd `id`.** ML-servicen skal derfor oversætte:
- ind: `movieId` fra `taste_signals` → Letterboxd `id`, før modellen kaldes
- ud: Letterboxd `id` fra modellen → `movieId`, før der skrives til `recommendations`

Byg gerne indekset **kun over film, der har et `movieId`**. Så kan alt, modellen anbefaler, slås op i appen,
og indekset bliver mindre (vigtigt på Render free tier med 512 MB RAM).

**Fejl, der skal rettes først:** MovieLens og Letterboxd er koblet sammen på eksakt titel. MovieLens skriver
artikler bagerst ("Matrix, The (1999)") og alternative titler i parentes ("Seven (a.k.a. Se7en)").
Derfor mangler 3.110 af de 9.742 film i `ml-latest-small`, heriblandt **36 af de 100 mest bedømte film**
(The Shawshank Redemption, The Matrix, The Godfather, Star Wars, The Dark Knight, Lord of the Rings …).
→ **Kobl på `tmdbId` eller `imdbId`** (fra MovieLens `links.csv`) i stedet for titel. Alternativt kan titlerne
normaliseres ("X, The" → "The X" og parenteser fjernes), før der matches.

**De ca. 40 film i appens onboarding-gitter skal alle findes i indekset.** Ellers bliver brugerens likes ignoreret, uden at nogen opdager det.

### Det, appen har brug for: 4 leverancer

**1. Rettet datasæt + ID-mapping** (se ovenfor). Mål: alle populære MovieLens-film er med, og hver har et Letterboxd `id`.

**2. Tabellen `movies` i Supabase, fyldt med datasættet.**
Appen slår titel, år, beskrivelse osv. op her for de film, I anbefaler, og bruger den til søgning i onboarding. Kun disse kolonner:

| Kolonne | Type | Fra CSV |
|---|---|---|
| `movie_id` | integer, primærnøgle | `movieId` |
| `tmdb_id` | integer, kan være null | `ml_tmdbId` |
| `imdb_id` | text | `ml_imdbId` |
| `title` | text | `letterboxd_name` |
| `year` | integer | `year` |
| `genres` | text[] | `lb_genres` (fald tilbage på `ml_genres`) |
| `description` | text | `description` |
| `runtime_minutes` | integer | `minute` |
| `letterboxd_rating` | real | `rating` |
| `themes` | text[] | `themes` |

Tabellen oprettes af SQL-filen. I fylder den, fx med et Python-script og service role key
(upsert i bidder på ca. 1.000 rækker).

**3. `POST /recommend`** (FastAPI), der kan nås fra en iPhone.

```
POST {ML_BASE_URL}/recommend
Authorization: Bearer <brugerens Supabase access token>
Content-Type: application/json

{ "context_id": null }
```

- **Find `user_id` ved at verificere tokenet** (`supabase.auth.get_user(token)`). Stol aldrig på et user_id i body.
- Læs brugerens rækker i `taste_signals` (`movie_id`, `signal`).
- Kør modellen med likes, og udelad alle film, brugeren har markeret.
- Sæt gerne `popularity_boost=0`. Appen skal anbefale ud fra smag, ikke popularitet.
- Skriv præcis 5 rækker til `recommendations`. Upsert på `(user_id, rank)`, så gamle rækker overskrives:

| Kolonne | Indhold |
|---|---|
| `user_id` | fra tokenet |
| `rank` | 1–5 |
| `movie_id` | MovieLens movieId (skal findes i `movies`) |
| `score` | modellens `similarity` (0–1). Appen viser den som match-score i procent |
| `reason` | **kort engelsk tekst, som vises direkte**, fx "Because you liked Se7en · Director: David Fincher · Themes: serial killer". Bygges ud fra `because` og `shared`. |
| `explanation` | (valgfri) modellens `breakdown` som jsonb, fx `[{"feature": "director", "label": "Director", "value": 0.13}]` |
| `model_version` | fx "2026-10-23-a" |

- **Svar** først **efter** rækkerne er skrevet: `200 {"status": "ok", "count": 5, "model_version": "..."}`
- **Fejl** (body: `{"error": "<kode>", "message": "..."}`, `message` på engelsk):

| Status | `error` | Hvornår |
|---|---|---|
| 401 | `invalid_token` | Token mangler, er ugyldigt eller udløbet |
| 422 | `too_few_likes` | Under 5 likes |
| 503 | `model_not_ready` | Modellen er ikke indlæst endnu |
| 500 | `internal` | Alt andet |

- Indlæs indekset én gang ved opstart. Indtil det er klar, svar 503.
- Appen venter højst 60 sekunder.

**4. Svar på de åbne spørgsmål** nederst.

### Sikkerhed

- ML-servicen bruger Supabase' **service role key** (går uden om Row Level Security).
  Nøglen ligger **kun** som miljøvariabel på serveren, aldrig i git og aldrig i appen.
- Appen bruger kun anon key og må kun læse sine egne `recommendations`.

### Sådan tester I uden appen

```bash
# 1. Opret en testbruger i Supabase → Authentication → Users (e-mail + adgangskode)

# 2. Hent et access token for brugeren
curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"hemmeligt123"}' | jq -r .access_token

# 3. Indsæt likes (og et dislike) i SQL Editor:
#    insert into taste_signals (user_id, movie_id, signal) values
#      ('<user-uuid>', 2571, 'like'),  ('<user-uuid>', 296, 'like'), ('<user-uuid>', 2959, 'like'),
#      ('<user-uuid>', 47, 'like'),    ('<user-uuid>', 4993, 'like'), ('<user-uuid>', 356, 'dislike');

# 4. Kald endpointet
curl -s -X POST "$ML_BASE_URL/recommend" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"context_id": null}'

# 5. Tjek: select * from recommendations where user_id = '<user-uuid>' order by rank;
```

Når trin 5 viser 5 rækker med fornuftige film (og ingen af dem fra trin 3), virker det også i appen.

### Tjekliste

- [ ] Datasættet er koblet på `tmdbId`/`imdbId`, og de populære film er med
- [ ] Mapping `movieId` ↔ Letterboxd `id` findes, og indekset er bygget over film med `movieId`
- [ ] De ca. 40 film i appens onboarding-gitter findes alle i indekset
- [ ] `movies` er fyldt i Supabase
- [ ] `POST /recommend` kører på en URL, som en iPhone kan nå (Render, eller lokalt via ngrok/samme Wi-Fi)
- [ ] Testen ovenfor giver 5 rækker i `recommendations` med en engelsk `reason`
- [ ] URL'en er sendt til Peter

### Åbne spørgsmål: svar til Peter

1. **URL:** Render, eller lokalt?
2. **`reason`:** Kan I levere den som engelsk tekst? Hvis ikke, viser appen genrerne.
3. **Minimum likes:** Er 5 nok? Og bruger I højst 25 (`MAX_LIKED`)?
4. **Kan alle 71.828 film anbefales**, eller filtrerer I (fx kun film med beskrivelse eller med en vis popularitet)?
5. **Indeksets størrelse:** Hvor mange MB fylder det, og hvor meget RAM bruger servicen?
6. **Dislikes:** Kan modellen senere trække film ned, der ligner brugerens dislikes?
