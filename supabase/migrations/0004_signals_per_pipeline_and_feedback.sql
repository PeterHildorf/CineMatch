-- CineMatch – migration 0004: svar pr. pipeline + måling af modellernes præcision
-- Køres i Supabase → SQL Editor EFTER 0002 (0003 er uafhængig).
--
-- Ændringer:
--   1. taste_signals: én like-bunke pr. pipeline (stars, swipe, search), stjerner og 'neutral'
--   2. recommendation_batches:     én række pr. "Get recommendations" (model, version, input)
--   3. recommendation_impressions: hver film, der faktisk blev VIST (nævneren i præcisionen)
--   4. recommendation_feedback:    "Seen it" → liked / disliked
--   5. Views til målinger: recommendation_metrics og recommendation_metrics_by_rank
--
-- Appen skriver kun sine egne rækker (RLS). Holdet læser målingerne i SQL Editor, som går uden om RLS.

begin;

-- ---------------------------------------------------------------------------
-- 1. taste_signals pr. pipeline
-- Swipe og søgning bruger begge Antons model (Letterboxd-id), men har hver sin like-bunke.
-- Stjerner bruger Mikkels model (TMDB-id). Derfor er pipeline en del af nøglen.
-- Eksisterende rækker kommer fra swipe-onboarding.
-- ---------------------------------------------------------------------------
alter table public.taste_signals
    add column pipeline   text not null default 'swipe' check (pipeline in ('stars', 'swipe', 'search')),
    add column rating     numeric(2, 1) check (rating between 0.5 and 5.0 and rating * 2 = floor(rating * 2)),
    add column updated_at timestamptz not null default now();

alter table public.taste_signals alter column pipeline drop default;

alter table public.taste_signals drop constraint taste_signals_signal_check;
alter table public.taste_signals add constraint taste_signals_signal_check
    check (signal in ('like', 'dislike', 'neutral'));

alter table public.taste_signals drop constraint taste_signals_pkey;
alter table public.taste_signals add primary key (user_id, pipeline, movie_id);

drop index public.taste_signals_user_signal_created_idx;
create index taste_signals_user_pipeline_updated_idx
    on public.taste_signals (user_id, pipeline, updated_at desc);

-- Skifter brugeren mening (upsert), bliver svaret det nyeste.
create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger taste_signals_touch_updated_at
    before update on public.taste_signals
    for each row execute function public.touch_updated_at();

comment on column public.taste_signals.source is
    'onboarding = swipe, stjerner eller søgning. feedback = "Seen it" på en anbefaling.';

-- ---------------------------------------------------------------------------
-- 2. recommendation_batches: ét resultat fra modellen
-- ---------------------------------------------------------------------------
create table public.recommendation_batches (
    id             uuid primary key,                    -- laves af appen, så events kan sendes i rækkefølge
    user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
    pipeline       text not null check (pipeline in ('stars', 'swipe', 'search')),
    model_version  text not null,                       -- modelVersion fra modelfilen
    input_count    integer not null,                    -- antal likes/stjerner, modellen fik
    created_at     timestamptz not null
);

create index recommendation_batches_user_idx on public.recommendation_batches (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 3. recommendation_impressions: film, brugeren har fået vist
-- rank = modellens placering (1 = bedst). shown_position = pladsen på skærmen,
-- som er anderledes, når "Only my services" filtrerer, eller en film er erstattet.
-- ---------------------------------------------------------------------------
create table public.recommendation_impressions (
    batch_id        uuid not null references public.recommendation_batches (id) on delete cascade,
    movie_id        integer not null,
    user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
    rank            integer not null check (rank >= 1),
    score           double precision,
    shown_position  integer not null check (shown_position >= 1),
    shown_at        timestamptz not null default now(),
    primary key (batch_id, movie_id)                     -- første visning tæller
);

-- ---------------------------------------------------------------------------
-- 4. recommendation_feedback: "Seen it"
-- ---------------------------------------------------------------------------
create table public.recommendation_feedback (
    batch_id    uuid not null references public.recommendation_batches (id) on delete cascade,
    movie_id    integer not null,
    user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    outcome     text not null check (outcome in ('seen_liked', 'seen_disliked')),
    created_at  timestamptz not null default now(),
    primary key (batch_id, movie_id)
);

-- ---------------------------------------------------------------------------
-- RLS: appen må læse og indsætte sine egne rækker. Ingen opdatering eller sletning.
-- ---------------------------------------------------------------------------
alter table public.recommendation_batches     enable row level security;
alter table public.recommendation_impressions enable row level security;
alter table public.recommendation_feedback    enable row level security;

create policy "Own batches: read"   on public.recommendation_batches for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Own batches: insert" on public.recommendation_batches for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Own impressions: read"   on public.recommendation_impressions for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Own impressions: insert" on public.recommendation_impressions for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Own feedback: read"   on public.recommendation_feedback for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Own feedback: insert" on public.recommendation_feedback for insert to authenticated
    with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 5. Målinger pr. pipeline og modelversion
--   seen_rate       = andel af viste film, brugeren har set (høj = modellen rammer kendte film)
--   precision_liked = liked / (liked + disliked) blandt sete film. Det primære præcisionsmål.
-- security_invoker: i appen ser brugeren kun sine egne tal. I SQL Editor ses alle.
-- ---------------------------------------------------------------------------
create view public.recommendation_metrics with (security_invoker = true) as
select
    b.pipeline,
    b.model_version,
    count(distinct b.user_id)                                          as users,
    count(distinct b.id)                                               as batches,
    count(*)                                                           as impressions,
    count(f.outcome)                                                   as seen,
    count(*) filter (where f.outcome = 'seen_liked')                   as seen_liked,
    count(*) filter (where f.outcome = 'seen_disliked')                as seen_disliked,
    round(count(f.outcome)::numeric / nullif(count(*), 0), 3)          as seen_rate,
    round((count(*) filter (where f.outcome = 'seen_liked'))::numeric
          / nullif(count(f.outcome), 0), 3)                            as precision_liked
from public.recommendation_batches b
join public.recommendation_impressions i on i.batch_id = b.id
left join public.recommendation_feedback f on f.batch_id = i.batch_id and f.movie_id = i.movie_id
group by b.pipeline, b.model_version;

-- Samme tal pr. modellens rank. Top-placeringerne bør have højest precision_liked.
-- Rank over 10 er erstatninger, der rykkede op efter "Seen it".
create view public.recommendation_metrics_by_rank with (security_invoker = true) as
select
    b.pipeline,
    b.model_version,
    i.rank,
    count(*)                                                           as impressions,
    count(f.outcome)                                                   as seen,
    count(*) filter (where f.outcome = 'seen_liked')                   as seen_liked,
    round(count(f.outcome)::numeric / nullif(count(*), 0), 3)          as seen_rate,
    round((count(*) filter (where f.outcome = 'seen_liked'))::numeric
          / nullif(count(f.outcome), 0), 3)                            as precision_liked
from public.recommendation_batches b
join public.recommendation_impressions i on i.batch_id = b.id
left join public.recommendation_feedback f on f.batch_id = i.batch_id and f.movie_id = i.movie_id
group by b.pipeline, b.model_version, i.rank;

commit;
