alter table public.carmitra_profiles add column if not exists date_of_birth date;
do $$begin
if not exists(select 1 from pg_constraint where conrelid='public.carmitra_profiles'::regclass and conname='carmitra_profiles_dob_valid')then
alter table public.carmitra_profiles add constraint carmitra_profiles_dob_valid check(date_of_birth is null or date_of_birth between date '1900-01-01' and (now() at time zone 'Asia/Kolkata')::date);
end if;
end $$;
comment on column public.carmitra_profiles.date_of_birth is 'Optional customer birth date; protected by existing owner/admin SELECT and owner UPDATE policies.';
notify pgrst,'reload schema';
