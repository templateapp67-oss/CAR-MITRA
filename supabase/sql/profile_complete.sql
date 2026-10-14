alter table public.carmitra_profiles add column if not exists gender text,add column if not exists contact_email text,add column if not exists photo_path text;
do $$begin
if not exists(select 1 from pg_constraint where conname='carmitra_profile_gender_valid' and conrelid='public.carmitra_profiles'::regclass)then
alter table public.carmitra_profiles add constraint carmitra_profile_gender_valid check(gender is null or gender in ('male','female','other')),
add constraint carmitra_profile_contact_email_valid check(contact_email is null or contact_email='' or (length(contact_email)<=254 and contact_email~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')),
add constraint carmitra_profile_photo_owner check(photo_path is null or (length(photo_path)<=500 and split_part(photo_path,'/',1)=user_id::text));
end if;end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('carmitra-avatars','carmitra-avatars',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
do $$begin
if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='carmitra_avatar_read_own')then
create policy carmitra_avatar_read_own on storage.objects for select to authenticated using(bucket_id='carmitra-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy carmitra_avatar_insert_own on storage.objects for insert to authenticated with check(bucket_id='carmitra-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy carmitra_avatar_delete_own on storage.objects for delete to authenticated using(bucket_id='carmitra-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
end if;end $$;
create table if not exists public.carmitra_reward_points(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,points integer not null check(points<>0),description text not null check(length(description)between 1 and 200),created_at timestamptz not null default now());
alter table public.carmitra_reward_points enable row level security;
revoke all on public.carmitra_reward_points from anon,authenticated;
grant select on public.carmitra_reward_points to authenticated;grant all on public.carmitra_reward_points to service_role;
do $$begin if not exists(select 1 from pg_policies where tablename='carmitra_reward_points' and policyname='reward_read_own')then
create policy reward_read_own on public.carmitra_reward_points for select to authenticated using(user_id=(select auth.uid()));end if;end $$;
create index if not exists carmitra_reward_points_user on public.carmitra_reward_points(user_id);
create or replace function public.carmitra_my_points()returns jsonb language sql stable security invoker set search_path='' as $$ select jsonb_build_object('balance',coalesce(sum(points),0),'earned',coalesce(sum(points)filter(where points>0),0),'used',-coalesce(sum(points)filter(where points<0),0)) from public.carmitra_reward_points where user_id=(select auth.uid()) $$;
revoke all on function public.carmitra_my_points()from public,anon;grant execute on function public.carmitra_my_points()to authenticated;
notify pgrst,'reload schema';
