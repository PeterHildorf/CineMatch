-- CineMatch – migration 0002: likes i stedet for 1–5 stjerner
-- Køres i Supabase → SQL Editor EFTER 0001_initial_schema.sql. Se docs/ml_contract.md.
--
-- Hvorfor: Antons model tager en liste af film, brugeren kan lide (recommend(liked_ids)).
-- Onboarding gemmer derfor likes/dislikes i taste_signals i stedet for stjerner i ratings.
--
-- Ændringer:
--   1. Ny tabel taste_signals (like/dislike) med RLS
--   2. Eksisterende ratings flyttes over (>= 4 → like, <= 2 → dislike, 3 springes over)
--   3. Tabellen ratings slettes
--   4. recommendations får kolonnen explanation (modellens breakdown, valgfri)

begin;

-- ---------------------------------------------------------------------------
-- 1. taste_signals: brugerens likes/dislikes (modellens input)
-- Én række pr. (bruger, film). Skifter brugeren mening, opdateres rækken.
-- source = 'feedback' bruges senere til tommel op/ned på anbefalinger.
-- ---------------------------------------------------------------------------
create table public.taste_signals (
    user_id     uuid not null references auth.users (id) on delete cascade,
    movie_id    integer not null,                                   -- Letterboxd id (fra modelfilen)
    signal      text not null check (signal in ('like', 'dislike')),
    source      text not null default 'onboarding' check (source in ('onboarding', 'feedback')),
    created_at  timestamptz not null default now(),
    primary key (user_id, movie_id)
);

-- ML-servicen henter "brugerens likes, nyeste først" – dette indeks gør det hurtigt.
create index taste_signals_user_signal_created_idx
    on public.taste_signals (user_id, signal, created_at desc);

alter table public.taste_signals enable row level security;

create policy "Own taste signals: all" on public.taste_signals for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 2. Flyt eksisterende testdata fra ratings (så ingen data går tabt)
-- ---------------------------------------------------------------------------
insert into public.taste_signals (user_id, movie_id, signal, source, created_at)
select user_id,
       movie_id,
       case when rating >= 4 then 'like' else 'dislike' end,
       'onboarding',
       created_at
from public.ratings
where rating >= 4 or rating <= 2
on conflict (user_id, movie_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. ratings udgår
-- ---------------------------------------------------------------------------
drop table public.ratings;

-- ---------------------------------------------------------------------------
-- 4. recommendations: forklaring til match-score og "why it matches"-søjler
-- Format: [{"feature": "director", "label": "Director", "value": 0.13}, ...]
-- ---------------------------------------------------------------------------
alter table public.recommendations add column explanation jsonb;

comment on column public.recommendations.reason is
    'Færdig tekst på engelsk, vises direkte i appen. Fx "Because you liked Se7en · Director: David Fincher"';
comment on column public.recommendations.score is
    'Modellens similarity (0–1). Appen viser den som match-score i procent';
comment on column public.recommendations.explanation is
    'Valgfri. Modellens breakdown: [{"feature", "label", "value"}]';

commit;
