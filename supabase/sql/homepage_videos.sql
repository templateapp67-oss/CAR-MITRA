create table public.carmitra_videos(
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(trim(title)) between 1 and 120),
 caption text not null default '' check(length(caption)<=500),
 source_type text not null check(source_type in ('youtube','upload')),
 youtube_id text check(youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
 storage_path text check(storage_path ~ '^[0-9a-f-]{36}/marketing/[0-9a-f-]{36}\.(mp4|webm)$'),
 poster_path text check(poster_path ~ '^[0-9a-f-]{36}/marketing/[0-9a-f-]{36}\.(jpg|png|webp)$'),
 sort_order integer not null default 0 check(sort_order between 0 and 10000),
 published boolean not null default false,
 created_at timestamptz not null default now(),
 constraint video_source check((source_type='youtube' and youtube_id is not null and storage_path is null) or (source_type='upload' and storage_path is not null and youtube_id is null))
);
alter table public.carmitra_videos enable row level security;
grant select on public.carmitra_videos to anon;
grant select,insert,update,delete on public.carmitra_videos to authenticated;
grant all on public.carmitra_videos to service_role;
create policy videos_published on public.carmitra_videos for select to anon,authenticated using(published);
create policy videos_admin_read on public.carmitra_videos for select to authenticated using((select carmitra_internal.is_admin()));
create policy videos_admin_insert on public.carmitra_videos for insert to authenticated with check((select carmitra_internal.is_admin()));
create policy videos_admin_update on public.carmitra_videos for update to authenticated using((select carmitra_internal.is_admin())) with check((select carmitra_internal.is_admin()));
create policy videos_admin_delete on public.carmitra_videos for delete to authenticated using((select carmitra_internal.is_admin()));
create index carmitra_videos_published_order on public.carmitra_videos(sort_order,created_at) where published;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('carmitra-marketing','carmitra-marketing',true,52428800,array['video/mp4','video/webm','image/jpeg','image/png','image/webp']);
create policy marketing_admin_read on storage.objects for select to authenticated using(bucket_id='carmitra-marketing' and (select carmitra_internal.is_admin()));
create policy marketing_admin_insert on storage.objects for insert to authenticated with check(bucket_id='carmitra-marketing' and (storage.foldername(name))[1]=(select auth.uid())::text and (select carmitra_internal.is_admin()));
create policy marketing_admin_update on storage.objects for update to authenticated using(bucket_id='carmitra-marketing' and (select carmitra_internal.is_admin())) with check(bucket_id='carmitra-marketing' and (select carmitra_internal.is_admin()));
create policy marketing_admin_delete on storage.objects for delete to authenticated using(bucket_id='carmitra-marketing' and (select carmitra_internal.is_admin()));
