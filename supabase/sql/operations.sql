begin;
alter table public.carmitra_partners add column latitude double precision check(latitude between 26.7 and 27.2),add column longitude double precision check(longitude between 75.5 and 76.1);
alter table public.carmitra_channel_partners add column latitude double precision check(latitude between 26.7 and 27.2),add column longitude double precision check(longitude between 75.5 and 76.1);
alter table public.carmitra_wallet_transactions drop constraint carmitra_wallet_transactions_kind_check;
alter table public.carmitra_wallet_transactions add constraint carmitra_wallet_transactions_kind_check check(kind in ('online_earning','cash_earning','cash_platform_due','cash_platform_payment','withdrawal_reserved','withdrawal_released'));
create table public.carmitra_channel_nominees(id uuid primary key default gen_random_uuid(),channel_user_id uuid not null references auth.users(id),full_name text not null,phone text not null check(phone~'^[6-9][0-9]{9}$'),locality text not null references public.carmitra_areas(locality),note text not null default '',status text not null default 'pending',created_at timestamptz not null default now());
alter table public.carmitra_channel_nominees enable row level security;
grant select on public.carmitra_channel_nominees to authenticated;
grant all on public.carmitra_channel_nominees to service_role;
create policy nominee_read on public.carmitra_channel_nominees for select to authenticated using(channel_user_id=(select auth.uid()) or (select carmitra_internal.is_admin()));
create index on public.carmitra_channel_nominees(channel_user_id);
create index on public.carmitra_channel_nominees(locality);
create function carmitra_internal.distance_km(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable set search_path='' as $$select 6371*acos(least(1.0,greatest(-1.0,sin(radians(a))*sin(radians(c))+cos(radians(a))*cos(radians(c))*cos(radians(d-b)))))$$;
create function carmitra_internal.operations(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();admin boolean;ch public.carmitra_channel_partners;b public.carmitra_bookings;partner public.carmitra_partners;lat double precision;lng double precision;due bigint;amount integer;result jsonb;begin
 if u is null then raise exception 'Sign in required';end if;admin:=carmitra_internal.is_admin();
 if op='partner_location' then
  lat:=(p->>'latitude')::double precision;lng:=(p->>'longitude')::double precision;if lat is null or lng is null then raise exception 'Location is required';end if;
  update public.carmitra_partners set latitude=lat,longitude=lng where user_id=u and active;if not found then raise exception 'Approved partner required';end if;return jsonb_build_object('saved',true);
 elsif op='channel_leads' then
  select * into ch from public.carmitra_channel_partners where user_id=u and active;
  return coalesce((select jsonb_agg(jsonb_build_object('id',bk.id,'starts_at',bk.starts_at,'status',bk.status,'locality',bk.address_snapshot->>'locality','services',bk.service_snapshot)) from public.carmitra_bookings bk where bk.address_snapshot->>'locality'=any(ch.localities) and (ch.tier='city' or (ch.tier='zone' and ch.latitude is not null and bk.address_snapshot->>'latitude' is not null and carmitra_internal.distance_km(ch.latitude,ch.longitude,(bk.address_snapshot->>'latitude')::double precision,(bk.address_snapshot->>'longitude')::double precision)<=3))),'[]'::jsonb);
 elsif op='zone_partners' then
  select * into ch from public.carmitra_channel_partners where user_id=u and active;if ch.user_id is null then raise exception 'Approved channel partner required';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',user_id,'full_name',full_name,'locality',locality)) from public.carmitra_partners where active and agreement_signed_at is not null and locality=any(ch.localities)),'[]'::jsonb);
 elsif op='nominate_partner' then
  select * into ch from public.carmitra_channel_partners where user_id=u and active and tier in ('zone','city');if ch.user_id is null or not (p->>'locality'=any(ch.localities)) then raise exception 'Choose your allocated Jaipur area';end if;
  if length(trim(p->>'full_name'))<2 then raise exception 'Enter nominee name';end if;
  insert into public.carmitra_channel_nominees(channel_user_id,full_name,phone,locality,note) values(u,p->>'full_name',p->>'phone',p->>'locality',coalesce(p->>'note',''));return jsonb_build_object('saved',true);
 elsif op='route_lead' then
  select * into ch from public.carmitra_channel_partners where user_id=u and active and tier in ('zone','city');
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and status in ('booked','partner_assigned') for update;
  if ch.user_id is null or b.id is null or not (b.address_snapshot->>'locality'=any(ch.localities)) then raise exception 'Lead outside your allocated area';end if;
  if ch.tier='zone' and (ch.latitude is null or b.address_snapshot->>'latitude' is null or carmitra_internal.distance_km(ch.latitude,ch.longitude,(b.address_snapshot->>'latitude')::double precision,(b.address_snapshot->>'longitude')::double precision)>3) then raise exception 'Verified address pin and configured 3 km zone required';end if;
 elsif not admin then raise exception 'Admin access required';end if;
 if op='set_zone_center' then
  lat:=(p->>'latitude')::double precision;lng:=(p->>'longitude')::double precision;if lat is null or lng is null then raise exception 'Enter the real zone centre';end if;
  update public.carmitra_channel_partners set latitude=lat,longitude=lng where user_id=(p->>'user_id')::uuid;
 elsif op='settle_cash_due' then
  perform pg_advisory_xact_lock(hashtextextended(p->>'user_id',0));select -coalesce(sum(amount_paise),0) into due from public.carmitra_wallet_transactions where user_id=(p->>'user_id')::uuid and kind in ('cash_platform_due','cash_platform_payment');amount:=(p->>'amount_paise')::integer;
  if amount is null or amount<=0 or amount>due or length(trim(coalesce(p->>'reference','')))<4 then raise exception 'Enter an actual received transfer reference and an amount within outstanding platform dues';end if;
  insert into public.carmitra_wallet_transactions(user_id,kind,amount_paise) values((p->>'user_id')::uuid,'cash_platform_payment',amount);
 elsif op in ('auto_assign','route_lead') then
  if op='auto_assign' then select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and status in ('booked','partner_assigned') for update;if b.id is null or b.address_snapshot->>'latitude' is null then raise exception 'An eligible booking and address GPS pin are required for nearest-partner assignment';end if;end if;
  select * into partner from public.carmitra_partners x where active and agreement_signed_at is not null and x.locality=b.address_snapshot->>'locality' and (op<>'auto_assign' or (x.latitude is not null and x.longitude is not null)) and (op<>'route_lead' or x.user_id=(p->>'partner_id')::uuid) and not exists(select 1 from public.carmitra_services z where z.id=any(b.service_ids) and not z.category=any(x.skills)) and not exists(select 1 from public.carmitra_bookings z where z.partner_id=x.user_id and z.id<>b.id and z.status not in ('cancelled','completed') and tstzrange(z.starts_at,z.starts_at+make_interval(mins=>z.duration_minutes),'[)')&&tstzrange(b.starts_at,b.starts_at+make_interval(mins=>b.duration_minutes),'[)')) order by case when op='auto_assign' then carmitra_internal.distance_km(x.latitude,x.longitude,(b.address_snapshot->>'latitude')::double precision,(b.address_snapshot->>'longitude')::double precision) else 0 end for update skip locked limit 1;
  if partner.user_id is null then raise exception 'No available verified partner with matching area, skills and location';end if;
  update public.carmitra_bookings set partner_id=partner.user_id,status='partner_assigned',partner_accepted=false where id=b.id;insert into public.carmitra_notifications(user_id,message) values(partner.user_id,'New Jaipur job assigned');
 else raise exception 'Unknown operation';end if;
 insert into public.carmitra_audit_logs(actor,action,payload) values(u,op,p);return jsonb_build_object('updated',true);
end $$;
create function public.carmitra_operations(op text,p jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select carmitra_internal.operations(op,p)$$;
revoke all on function carmitra_internal.distance_km(double precision,double precision,double precision,double precision),carmitra_internal.operations(text,jsonb),public.carmitra_operations(text,jsonb) from public,anon;
grant execute on function carmitra_internal.operations(text,jsonb),public.carmitra_operations(text,jsonb) to authenticated;
commit;
