create or replace function carmitra_internal.create_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare contact_phone text := trim(coalesce(new.raw_user_meta_data->>'phone',''));
begin
 if contact_phone !~ '^[6-9][0-9]{9}$' then contact_phone := ''; end if;
 insert into public.carmitra_profiles(user_id,full_name,phone)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),contact_phone)
 on conflict(user_id) do nothing;
 return new;
end $$;
revoke all on function carmitra_internal.create_profile() from public,anon,authenticated;
