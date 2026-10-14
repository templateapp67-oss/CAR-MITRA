begin;
alter table public.carmitra_videos add column if not exists instagram_url text;
alter table public.carmitra_videos add column if not exists submitted_by uuid default auth.uid();
alter table public.carmitra_videos add column if not exists storage_bucket text not null default 'carmitra-marketing' check(storage_bucket in ('carmitra-marketing','carmitra-community'));
alter table public.carmitra_videos drop constraint carmitra_videos_source_type_check;
alter table public.carmitra_videos add constraint carmitra_videos_source_type_check check(source_type in ('youtube','instagram','upload'));
alter table public.carmitra_videos add constraint instagram_video_url check(instagram_url is null or instagram_url ~ '^https://www\.instagram\.com/(reel|p|tv)/[A-Za-z0-9_-]{5,64}/$');
alter table public.carmitra_videos drop constraint video_source;
alter table public.carmitra_videos add constraint video_source check(
 (source_type='youtube' and youtube_id is not null and instagram_url is null and storage_path is null) or
 (source_type='instagram' and instagram_url is not null and youtube_id is null and storage_path is null) or
 (source_type='upload' and storage_path is not null and youtube_id is null and instagram_url is null));
create policy videos_submitter_read on public.carmitra_videos for select to authenticated using(submitted_by=(select auth.uid()));
create policy videos_submitter_insert on public.carmitra_videos for insert to authenticated with check(
 submitted_by=(select auth.uid()) and not published and sort_order=0 and storage_bucket='carmitra-community' and
 (storage_path is null or split_part(storage_path,'/',1)=(select auth.uid())::text) and
 (poster_path is null or split_part(poster_path,'/',1)=(select auth.uid())::text));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('carmitra-community','carmitra-community',false,52428800,array['video/mp4','video/webm','image/jpeg','image/png','image/webp']);
create policy community_upload on storage.objects for insert to authenticated with check(bucket_id='carmitra-community' and (storage.foldername(name))[1]=(select auth.uid())::text and name ~ '^[0-9a-f-]{36}/marketing/[0-9a-f-]{36}\.(mp4|webm|jpg|png|webp)$');
create policy community_owner_admin_read on storage.objects for select to authenticated using(bucket_id='carmitra-community' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select carmitra_internal.is_admin())));
create policy community_published_read on storage.objects for select to anon,authenticated using(bucket_id='carmitra-community' and exists(select 1 from public.carmitra_videos v where v.published and v.storage_bucket='carmitra-community' and (v.storage_path=name or v.poster_path=name)));
create policy community_failed_upload_cleanup on storage.objects for delete to authenticated using(bucket_id='carmitra-community' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.carmitra_videos v where v.storage_bucket='carmitra-community' and (v.storage_path=name or v.poster_path=name)));
create policy community_admin_delete on storage.objects for delete to authenticated using(bucket_id='carmitra-community' and (select carmitra_internal.is_admin()));
create index carmitra_videos_submitter on public.carmitra_videos(submitted_by);
notify pgrst,'reload schema';
commit;
