-- Bounded public feed; private editing preserves moderation and booking ownership.
create or replace function carmitra_internal.review_feed(p_page integer,p_rating integer,p_sort text,p_search text) returns jsonb language sql stable security definer set search_path='' as $$
with filtered as (select r.*,coalesce(b.service_snapshot->0->>'name','Vehicle care') service from public.carmitra_reviews r join public.carmitra_bookings b on b.id=r.booking_id where r.published and (p_rating is null or r.rating=p_rating) and (coalesce(p_search,'')='' or r.body ilike '%'||left(p_search,80)||'%' or r.display_name ilike '%'||left(p_search,80)||'%')),
items as (select display_name,rating,body,created_at,service from filtered order by case when p_sort='highest' then rating end desc,case when p_sort='lowest' then rating end asc,created_at desc,id desc limit 12 offset greatest(0,least(coalesce(p_page,1),10000)-1)*12),
summary as (select count(*) total,round(avg(rating),1) average,jsonb_build_object('1',count(*)filter(where rating=1),'2',count(*)filter(where rating=2),'3',count(*)filter(where rating=3),'4',count(*)filter(where rating=4),'5',count(*)filter(where rating=5)) distribution from public.carmitra_reviews where published)
select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(items))from items),'[]'::jsonb),'matching',(select count(*)from filtered),'summary',(select to_jsonb(summary)from summary),'page',greatest(1,coalesce(p_page,1)));
$$;
create or replace function public.carmitra_review_feed(p_page integer default 1,p_rating integer default null,p_sort text default 'newest',p_search text default '') returns jsonb language sql stable security invoker set search_path='' as $$ select carmitra_internal.review_feed(p_page,p_rating,p_sort,p_search) $$;
create or replace function carmitra_internal.save_review(p_booking uuid,p_name text,p_rating integer,p_body text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.carmitra_reviews;begin
if u is null then raise exception 'Sign in to review your completed service';end if;
perform 1 from public.carmitra_bookings where id=p_booking and user_id=u and status='completed' for share;if not found then raise exception 'Reviews require your own completed booking';end if;
if length(trim(p_name)) not between 1 and 80 or length(trim(p_body)) not between 10 and 2000 or p_rating not between 1 and 5 or p_rating is null then raise exception 'Add a display name, 1–5 rating and 10–2000 characters of feedback';end if;
insert into public.carmitra_reviews(booking_id,user_id,display_name,rating,body) values(p_booking,u,trim(p_name),p_rating,trim(p_body)) on conflict(booking_id) do update set display_name=excluded.display_name,rating=excluded.rating,body=excluded.body where public.carmitra_reviews.user_id=u returning * into r;
if r.id is null then raise exception 'You cannot edit another customer review';end if;
return jsonb_build_object('saved',true,'published',r.published);
end $$;
create or replace function public.carmitra_save_review(p_booking uuid,p_name text,p_rating integer,p_body text) returns jsonb language sql security invoker set search_path='' as $$ select carmitra_internal.save_review(p_booking,p_name,p_rating,p_body) $$;
revoke all on function carmitra_internal.review_feed(integer,integer,text,text),public.carmitra_review_feed(integer,integer,text,text),carmitra_internal.save_review(uuid,text,integer,text),public.carmitra_save_review(uuid,text,integer,text) from public,anon;
grant execute on function carmitra_internal.review_feed(integer,integer,text,text),public.carmitra_review_feed(integer,integer,text,text) to anon,authenticated;
grant execute on function carmitra_internal.save_review(uuid,text,integer,text),public.carmitra_save_review(uuid,text,integer,text) to authenticated;
create index if not exists carmitra_reviews_public_date on public.carmitra_reviews(created_at desc) where published;
notify pgrst,'reload schema';
