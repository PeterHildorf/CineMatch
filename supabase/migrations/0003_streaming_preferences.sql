-- 0003: brugerens streamingtjenester. Bruges af SupabasePreferencesService.
-- Tjenesterne bruges kun af appens filter ("Only my services"), aldrig som modelinput.
--
-- streaming_services:
--   null = brugeren har aldrig valgt (så vises "Which services do you have?" efter login)
--   '{}' = brugeren har valgt "I don't have any"

begin;

alter table public.preferences
    add column streaming_services text[]
        check (streaming_services <@ array['netflix', 'primeVideo', 'disneyPlus', 'hboMax', 'appleTVPlus', 'viaplay', 'tv2Play']),
    add column only_my_services   boolean not null default false;

comment on column public.preferences.streaming_services is
    'Valgte tjenester (StreamingService.rawValue i appen). Null = aldrig valgt, tom = ingen tjenester.';

commit;
