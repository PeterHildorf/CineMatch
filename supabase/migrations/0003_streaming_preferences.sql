-- 0003: brugerens streamingtjenester (skrevet 30/10, IKKE kørt endnu).
-- I dag gemmes valget lokalt på telefonen (LocalPreferencesService).
-- Køres, når der laves en SupabasePreferencesService.
-- Tjenesterne bruges kun af appens filter ("Only my services"), aldrig som modelinput.

begin;

alter table public.preferences
    add column streaming_services text[] not null default '{}'
        check (streaming_services <@ array['netflix', 'primeVideo', 'disneyPlus', 'hboMax', 'appleTVPlus', 'viaplay', 'tv2Play']),
    add column only_my_services   boolean not null default false;

comment on column public.preferences.streaming_services is
    'Valgte tjenester (StreamingService.rawValue i appen). Tom = ingen valgt.';

commit;
