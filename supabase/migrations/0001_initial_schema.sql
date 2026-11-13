-- CineMatch – første skema (variant A)
-- Køres i Supabase → SQL Editor. Se docs/ml_contract.md for forklaring.
--
-- Regler:
--   * Appen (rollen "authenticated") må kun læse/skrive sine egne rækker.
--   * ML-servicen bruger service role key og går uden om RLS. Den nøgle må ALDRIG ligge i appen.
--   * movie_id er altid MovieLens movieId.

-- ---------------------------------------------------------------------------
-- movies: filmkataloget fra merged_datasets.csv (MovieLens + Letterboxd)
-- Fyldes af ML-teamet. Alle må læse, kun service role skriver.
-- ---------------------------------------------------------------------------
create table public.movies (
    movie_id           integer primary key,      -- MovieLens movieId
    tmdb_id            integer,
    imdb_id            text,
    title              text not null,
    year               integer,
    genres             text[] not null default '{}',
    description        text,
    runtime_minutes    integer,
    letterboxd_rating  real,
    themes             text[] not null default '{}'
);

-- ---------------------------------------------------------------------------
-- profiles: én række pr. bruger, oprettes automatisk ved signup
-- ---------------------------------------------------------------------------
create table public.profiles (
    id                       uuid primary key references auth.users (id) on delete cascade,
    created_at               timestamptz not null default now(),
    onboarding_completed_at  timestamptz
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
    insert into public.profiles (id) values (new.id);
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- ratings: brugerens bedømmelser (modellens input)
-- Skala som MovieLens: 0.5–5.0 i trin af 0.5. Én række pr. (bruger, film).
-- ---------------------------------------------------------------------------
create table public.ratings (
    user_id     uuid not null references auth.users (id) on delete cascade,
    movie_id    integer not null,
    rating      numeric(2, 1) not null check (rating between 0.5 and 5.0 and rating * 2 = floor(rating * 2)),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    primary key (user_id, movie_id)
);

-- ---------------------------------------------------------------------------
-- preferences: generelle præferencer fra onboarding (bruges efter torsdag)
-- ---------------------------------------------------------------------------
create table public.preferences (
    user_id          uuid primary key references auth.users (id) on delete cascade,
    favorite_genres  text[] not null default '{}',   -- MovieLens-genrer, fx 'Comedy', 'Sci-Fi'
    updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- viewing_contexts: "Hvad vil du se i dag?" (bruges efter torsdag)
-- ---------------------------------------------------------------------------
create table public.viewing_contexts (
    id                      uuid primary key default gen_random_uuid(),
    user_id                 uuid not null references auth.users (id) on delete cascade,
    mood                    text,        -- fx 'light', 'intense', 'thoughtful'
    time_available_minutes  integer,
    company                 text,        -- 'alone' eller 'together'
    created_at              timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- recommendations: top 5 skrevet af ML-servicen (modellens output)
-- ML-servicen sletter brugerens gamle rækker og indsætter nye 1–5.
-- ---------------------------------------------------------------------------
create table public.recommendations (
    user_id        uuid not null references auth.users (id) on delete cascade,
    rank           smallint not null check (rank between 1 and 5),
    movie_id       integer not null,
    score          real,
    reason         text,                 -- færdig tekst på engelsk, vises direkte i appen (ændret i 0002)
    model_version  text,
    context_id     uuid references public.viewing_contexts (id) on delete set null,
    created_at     timestamptz not null default now(),
    primary key (user_id, rank)
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.movies            enable row level security;
alter table public.profiles          enable row level security;
alter table public.ratings           enable row level security;
alter table public.preferences       enable row level security;
alter table public.viewing_contexts  enable row level security;
alter table public.recommendations   enable row level security;

create policy "Movies: everyone can read" on public.movies for select to anon, authenticated using (true);

create policy "Own profile: read"  on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "Own profile: update" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Own ratings: all" on public.ratings for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "Own preferences: all" on public.preferences for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "Own contexts: all" on public.viewing_contexts for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Appen må kun LÆSE anbefalinger. Kun ML-servicen (service role) skriver.
create policy "Own recommendations: read" on public.recommendations for select to authenticated
    using ((select auth.uid()) = user_id);
