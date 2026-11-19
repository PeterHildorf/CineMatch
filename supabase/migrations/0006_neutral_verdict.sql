-- CineMatch – migration 0006: Neutral på skalaen
-- Køres i Supabase → SQL Editor EFTER 0005.
--
-- Ny skala (tallet er modellernes input):
--   Haven't seen 0 · Horrible 1 · Bad 2 · Neutral 3 · Great 4 · Fantastic 5
--
-- Før (0005) var Great = 3. De rækker flyttes til 4, så de ikke pludselig læses som Neutral.
-- "Haven't seen" (0) gemmes stadig, men appen viser filmen i Swipe igen efter 14 dage.
--
-- Ændringer:
--   1. taste_signals: Great 3 → 4. Gamle stjerner (signal 'neutral', rating 3) bliver Neutral, som de skal.
--   2. recommendation_feedback.score: Great 3 → 4, og check tillader nu 1–5.
--   3. recommendation_metrics_by_score får en kolonne til Neutral.

begin;

-- ---------------------------------------------------------------------------
-- 1. taste_signals
-- ---------------------------------------------------------------------------
-- Kun 'like'-rækker: dem gemte appen som Great = 3. Triggeren fra 0004 ville sætte updated_at
-- til nu, så den slås fra under opdateringen (ellers ser det ud, som om alt er bedømt i dag).
alter table public.taste_signals disable trigger taste_signals_touch_updated_at;

update public.taste_signals
set rating = 4
where rating = 3 and signal = 'like';

alter table public.taste_signals enable trigger taste_signals_touch_updated_at;

comment on column public.taste_signals.rating is
    'Skalaen: 0 = Haven''t seen, 1 = Horrible, 2 = Bad, 3 = Neutral, 4 = Great, 5 = Fantastic. Halve værdier er gamle stjerner (før 0005).';
comment on column public.taste_signals.signal is
    'Grov version af rating: like (4, 5), neutral (3), dislike (1, 2), unseen (0).';

-- ---------------------------------------------------------------------------
-- 2. recommendation_feedback.score
-- ---------------------------------------------------------------------------
alter table public.recommendation_feedback drop constraint if exists recommendation_feedback_score_check;

update public.recommendation_feedback
set score = 4
where score = 3;

alter table public.recommendation_feedback add constraint recommendation_feedback_score_check
    check (score between 1 and 5);

comment on column public.recommendation_feedback.score is
    'Dommen ved "Seen it": 1 = Horrible, 2 = Bad, 3 = Neutral, 4 = Great, 5 = Fantastic. outcome: 4–5 = seen_liked, 1–3 = seen_disliked.';

-- ---------------------------------------------------------------------------
-- 3. Fordeling af domme pr. pipeline og model
-- ---------------------------------------------------------------------------
drop view if exists public.recommendation_metrics_by_score;

create view public.recommendation_metrics_by_score with (security_invoker = true) as
select
    b.pipeline,
    b.model_version,
    count(*) filter (where f.score = 1)                               as horrible,
    count(*) filter (where f.score = 2)                               as bad,
    count(*) filter (where f.score = 3)                               as neutral,
    count(*) filter (where f.score = 4)                               as great,
    count(*) filter (where f.score = 5)                               as fantastic,
    round(avg(f.score), 2)                                            as avg_score
from public.recommendation_batches b
join public.recommendation_feedback f on f.batch_id = b.id
where f.score is not null
group by b.pipeline, b.model_version;

commit;

notify pgrst, 'reload schema';
