-- CineMatch – migration 0005: én fælles skala til alle bedømmelser
-- Køres i Supabase → SQL Editor EFTER 0004.
--
-- Swipe, "Seen it" og Search bruger nu samme fem knapper. Tallet er modellernes input:
--   Haven't seen 0 · Horrible 1 · Bad 2 · Great 3 · Fantastic 5   (ingen 4 – bevidst)
--
-- Ændringer:
--   1. taste_signals.rating er nu skalaens tal (0, 1, 2, 3, 5). Gamle ½–5-stjerner må blive liggende.
--   2. taste_signals.signal kan også være 'unseen' ("Haven't seen" gemmes, så filmen ikke vises igen).
--   3. recommendation_feedback.score: den præcise dom ved "Seen it". outcome (liked/disliked) beholdes,
--      så recommendation_metrics virker uændret. Great/Fantastic = seen_liked.
--   4. Nyt view recommendation_metrics_by_score: fordeling af domme pr. pipeline og model.

begin;

-- ---------------------------------------------------------------------------
-- 1 + 2. taste_signals
-- ---------------------------------------------------------------------------
alter table public.taste_signals drop constraint if exists taste_signals_rating_check;
alter table public.taste_signals add constraint taste_signals_rating_check
    check (rating between 0 and 5 and rating * 2 = floor(rating * 2));   -- tillader også gamle halve stjerner

alter table public.taste_signals drop constraint taste_signals_signal_check;
alter table public.taste_signals add constraint taste_signals_signal_check
    check (signal in ('like', 'dislike', 'neutral', 'unseen'));          -- 'neutral' kun i gamle stjerne-rækker

comment on column public.taste_signals.rating is
    'Skalaen: 0 = Haven''t seen, 1 = Horrible, 2 = Bad, 3 = Great, 5 = Fantastic. Halve værdier er gamle stjerner (før 0005).';
comment on column public.taste_signals.signal is
    'Grov version af rating: like (3, 5), dislike (1, 2), unseen (0). Til modeller, der kun tager likes.';

-- ---------------------------------------------------------------------------
-- 3. recommendation_feedback.score
-- ---------------------------------------------------------------------------
alter table public.recommendation_feedback
    add column score smallint check (score in (1, 2, 3, 5));   -- null = logget før 0005

-- ---------------------------------------------------------------------------
-- 4. Fordeling af domme. Høj andel 5 = modellen rammer plet, høj andel 1 = den rammer helt forbi.
-- ---------------------------------------------------------------------------
create view public.recommendation_metrics_by_score with (security_invoker = true) as
select
    b.pipeline,
    b.model_version,
    count(*) filter (where f.score = 1)                               as horrible,
    count(*) filter (where f.score = 2)                               as bad,
    count(*) filter (where f.score = 3)                               as great,
    count(*) filter (where f.score = 5)                               as fantastic,
    round(avg(f.score), 2)                                            as avg_score
from public.recommendation_batches b
join public.recommendation_feedback f on f.batch_id = b.id
where f.score is not null
group by b.pipeline, b.model_version;

commit;
