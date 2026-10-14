-- Apply ONLY to the dedicated CarMitra Supabase project. Production catalogue is in catalogue.sql.
begin;
create schema if not exists carmitra_internal;
revoke all on schema carmitra_internal from public, anon;
grant usage on schema carmitra_internal to authenticated;
create table public.carmitra_services(id integer primary key,name text not null,category integer not null check(category between 0 and 4),price_paise integer check(price_paise>0),duration_minutes integer check(duration_minutes>0),active boolean not null default true);
create table public.carmitra_vehicle_multipliers(vehicle_type text primary key check(vehicle_type in ('hatchback','sedan','suv','bike')),basis_points integer not null default 10000 check(basis_points between 1000 and 100000));
create table public.carmitra_areas(locality text primary key,active boolean not null default true);
create table public.carmitra_vehicles(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,vehicle_type text not null references public.carmitra_vehicle_multipliers(vehicle_type),brand text not null check(length(trim(brand)) between 1 and 60),model text not null check(length(trim(model)) between 1 and 60),registration text not null check(registration ~ '^[A-Z0-9-]{5,20}$'),fuel text not null check(fuel in ('Petrol','Diesel','Electric','CNG','Hybrid')),created_at timestamptz not null default now());
create table public.carmitra_addresses(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,label text not null check(length(trim(label)) between 1 and 40),line1 text not null check(length(trim(line1)) between 8 and 300),locality text not null references public.carmitra_areas(locality),city text not null default 'Jaipur' check(city='Jaipur'),pin_code text not null check(pin_code ~ '^302[0-9]{3}$'),latitude double precision check(latitude between 26.7 and 27.2),longitude double precision check(longitude between 75.5 and 76.1),created_at timestamptz not null default now(),check((latitude is null)=(longitude is null)));
-- Admin publishes genuine capacity only. No demo or invented service slots.
create table public.carmitra_slots(id uuid primary key default gen_random_uuid(),starts_at timestamptz not null,ends_at timestamptz not null,capacity integer not null check(capacity between 1 and 100),active boolean not null default true,check(ends_at>starts_at),exclude using gist (tstzrange(starts_at,ends_at,'[)') with &&));
create table public.carmitra_bookings(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),vehicle_id uuid not null references public.carmitra_vehicles(id),address_id uuid not null references public.carmitra_addresses(id),slot_id uuid not null references public.carmitra_slots(id),service_ids integer[] not null,vehicle_snapshot jsonb not null,address_snapshot jsonb not null,service_snapshot jsonb not null,starts_at timestamptz not null,total_paise integer not null check(total_paise>0),duration_minutes integer not null check(duration_minutes>0),payment_method text not null check(payment_method in ('cash','razorpay')),payment_status text not null check(payment_status in ('cash_due','pending','paid')),status text not null default 'booked' check(status in ('awaiting_payment','booked','partner_assigned','on_the_way','started','completed','cancelled')),expires_at timestamptz,request_id uuid not null,created_at timestamptz not null default now(),unique(user_id,request_id));
create table public.carmitra_payment_orders(booking_id uuid primary key references public.carmitra_bookings(id),order_id text unique not null,amount_paise integer not null check(amount_paise>0),payment_id text unique,paid_at timestamptz,created_at timestamptz not null default now());
create table public.carmitra_booking_status_logs(id bigint generated always as identity primary key,booking_id uuid not null references public.carmitra_bookings(id),user_id uuid not null references auth.users(id),status text not null,created_at timestamptz not null default now());
create index on public.carmitra_vehicles(user_id);
create index on public.carmitra_addresses(user_id);
create index on public.carmitra_bookings(user_id,created_at desc);
create index on public.carmitra_bookings(slot_id,status);
create index on public.carmitra_booking_status_logs(user_id);
alter table public.carmitra_services enable row level security;
alter table public.carmitra_vehicle_multipliers enable row level security;
alter table public.carmitra_areas enable row level security;
alter table public.carmitra_vehicles enable row level security;
alter table public.carmitra_addresses enable row level security;
alter table public.carmitra_slots enable row level security;
alter table public.carmitra_bookings enable row level security;
alter table public.carmitra_payment_orders enable row level security;
alter table public.carmitra_booking_status_logs enable row level security;
revoke all on public.carmitra_services,public.carmitra_vehicle_multipliers,public.carmitra_areas,public.carmitra_vehicles,public.carmitra_addresses,public.carmitra_slots,public.carmitra_bookings,public.carmitra_payment_orders,public.carmitra_booking_status_logs from anon,authenticated;
grant select on public.carmitra_services,public.carmitra_vehicle_multipliers,public.carmitra_areas to anon,authenticated;
grant select,insert on public.carmitra_vehicles,public.carmitra_addresses to authenticated;
grant select on public.carmitra_bookings,public.carmitra_booking_status_logs to authenticated;
grant all on public.carmitra_services,public.carmitra_vehicle_multipliers,public.carmitra_areas,public.carmitra_vehicles,public.carmitra_addresses,public.carmitra_slots,public.carmitra_bookings,public.carmitra_payment_orders,public.carmitra_booking_status_logs to service_role;
grant usage,select on sequence public.carmitra_booking_status_logs_id_seq to service_role;
create policy catalogue_read on public.carmitra_services for select to anon,authenticated using(active);
create policy multiplier_read on public.carmitra_vehicle_multipliers for select to anon,authenticated using(true);
create policy area_read on public.carmitra_areas for select to anon,authenticated using(active);
create policy vehicle_read on public.carmitra_vehicles for select to authenticated using(user_id=(select auth.uid()));
create policy vehicle_create on public.carmitra_vehicles for insert to authenticated with check(user_id=(select auth.uid()));
create policy address_read on public.carmitra_addresses for select to authenticated using(user_id=(select auth.uid()));
create policy address_create on public.carmitra_addresses for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.carmitra_areas a where a.locality=carmitra_addresses.locality and a.active));
create policy booking_read on public.carmitra_bookings for select to authenticated using(user_id=(select auth.uid()));
create policy log_read on public.carmitra_booking_status_logs for select to authenticated using(user_id=(select auth.uid()));
create table public.carmitra_runtime_settings(id boolean primary key default true check(id),online_test_enabled boolean not null default false);
alter table public.carmitra_runtime_settings enable row level security;
revoke all on public.carmitra_runtime_settings from anon,authenticated;
grant all on public.carmitra_runtime_settings to service_role;
insert into public.carmitra_runtime_settings(id) values(true);
-- No client mutation policy for bookings, amounts, payment orders or slot capacity.
create function carmitra_internal.quote(p_vehicle uuid,p_services integer[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();v text;m integer;n integer;t bigint;d integer;
begin
 if u is null then raise exception 'Sign in required';end if;
 select vehicle_type into v from public.carmitra_vehicles where id=p_vehicle and user_id=u;
 if v is null then raise exception 'Vehicle not found';end if;
 if p_services is null or cardinality(p_services)<1 or cardinality(p_services)>10 or cardinality(p_services)<>(select count(distinct x) from unnest(p_services) x) then raise exception 'Choose 1–10 unique services';end if;
 select basis_points into m from public.carmitra_vehicle_multipliers where vehicle_type=v;
 select count(*),sum(price_paise::bigint),sum(duration_minutes) into n,t,d from public.carmitra_services where id=any(p_services) and active and price_paise is not null and duration_minutes is not null and ((v='bike' and category=4) or (v<>'bike' and category<>4));
 if n<>cardinality(p_services) then raise exception 'Some selected services are unavailable or unpriced';end if;
 t:=round(t*m/10000.0);if t>100000000 then raise exception 'Invalid service total';end if;
 return jsonb_build_object('total_paise',t,'duration_minutes',d);
end $$;
create function public.carmitra_quote(p_vehicle uuid,p_services integer[]) returns jsonb language sql security invoker set search_path='' as $$ select carmitra_internal.quote(p_vehicle,p_services) $$;
create function carmitra_internal.available_slots(p_date date,p_services integer[]) returns table(id uuid,starts_at timestamptz,remaining integer) language plpgsql security definer set search_path='' as $$
declare d integer;n integer;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select count(*),sum(duration_minutes) into n,d from public.carmitra_services where id=any(p_services) and active and price_paise is not null;
 if n<>cardinality(p_services) or d is null then raise exception 'Select available services';end if;
 return query select s.id,s.starts_at,(s.capacity-count(b.id))::integer from public.carmitra_slots s left join public.carmitra_bookings b on b.slot_id=s.id and b.status<>'cancelled' and (b.status<>'awaiting_payment' or b.expires_at>now()) where s.active and (s.starts_at at time zone 'Asia/Kolkata')::date=p_date and s.starts_at>now()+interval '30 minutes' and s.starts_at<now()+interval '30 days' and s.ends_at-s.starts_at>=make_interval(mins=>d) group by s.id having count(b.id)<s.capacity order by s.starts_at;
end $$;
create function public.carmitra_available_slots(p_date date,p_services integer[]) returns table(id uuid,starts_at timestamptz,remaining integer) language sql security invoker set search_path='' as $$ select * from carmitra_internal.available_slots(p_date,p_services) $$;
create function carmitra_internal.create_booking(p_vehicle uuid,p_services integer[],p_address uuid,p_slot uuid,p_payment text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();q jsonb;s public.carmitra_slots;a public.carmitra_addresses;v public.carmitra_vehicles;existing public.carmitra_bookings;b public.carmitra_bookings;used integer;items jsonb;
begin
 if u is null then raise exception 'Sign in required';end if;
 if p_request is null or p_payment is null or p_payment not in ('cash','razorpay') then raise exception 'Invalid booking request';end if;
 if p_payment='razorpay' and not coalesce((select online_test_enabled from public.carmitra_runtime_settings where id=true),false) then raise exception 'Online payment is not configured yet';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||p_request::text,0));
 select * into existing from public.carmitra_bookings where user_id=u and request_id=p_request;
 if existing.id is not null then return to_jsonb(existing);end if;
 if (select count(*) from public.carmitra_bookings where user_id=u and created_at>now()-interval '1 hour')>=10 then raise exception 'Booking limit reached. Please try later';end if;
 q:=carmitra_internal.quote(p_vehicle,p_services);
 select * into v from public.carmitra_vehicles where id=p_vehicle and user_id=u;
 select * into a from public.carmitra_addresses where id=p_address and user_id=u and city='Jaipur';
 if a.id is null or not exists(select 1 from public.carmitra_areas where locality=a.locality and active) then raise exception 'Choose a supported Jaipur address';end if;
 select * into s from public.carmitra_slots where id=p_slot and active for update;
 if s.id is null or s.starts_at<now()+interval '30 minutes' or s.starts_at>now()+interval '30 days' or s.ends_at-s.starts_at<make_interval(mins=>(q->>'duration_minutes')::integer) then raise exception 'This slot is no longer available';end if;
 select count(*) into used from public.carmitra_bookings where slot_id=p_slot and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());
 if used>=s.capacity then raise exception 'This slot has just filled. Please select another';end if;
 select jsonb_agg(jsonb_build_object('id',id,'name',name,'price_paise',price_paise,'duration_minutes',duration_minutes)) into items from public.carmitra_services where id=any(p_services);
 insert into public.carmitra_bookings(user_id,vehicle_id,address_id,slot_id,service_ids,vehicle_snapshot,address_snapshot,service_snapshot,starts_at,total_paise,duration_minutes,payment_method,payment_status,status,expires_at,request_id) values(u,p_vehicle,p_address,p_slot,p_services,to_jsonb(v)-'user_id',to_jsonb(a)-'user_id',items,s.starts_at,(q->>'total_paise')::integer,(q->>'duration_minutes')::integer,p_payment,case when p_payment='cash' then 'cash_due' else 'pending' end,case when p_payment='cash' then 'booked' else 'awaiting_payment' end,case when p_payment='razorpay' then now()+interval '15 minutes' else null end,p_request) returning * into b;
 insert into public.carmitra_booking_status_logs(booking_id,user_id,status) values(b.id,u,b.status);
 return to_jsonb(b);
end $$;
create function public.carmitra_create_booking(p_vehicle uuid,p_services integer[],p_address uuid,p_slot uuid,p_payment text,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$ select carmitra_internal.create_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request) $$;
-- Called only after server verifies a captured Razorpay payment of the exact amount.
create function carmitra_internal.mark_paid(p_booking uuid,p_order text,p_payment text) returns boolean language plpgsql security definer set search_path='' as $$
declare b public.carmitra_bookings;slot public.carmitra_slots;used integer;
begin
 select * into b from public.carmitra_bookings where id=p_booking for update;
 if b.id is null or b.payment_method<>'razorpay' then raise exception 'Invalid booking';end if;
 if b.payment_status='paid' then return true;end if;
 select * into slot from public.carmitra_slots where id=b.slot_id for update;
 if b.expires_at<now() then
  select count(*) into used from public.carmitra_bookings where slot_id=b.slot_id and id<>b.id and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());
  if used>=slot.capacity or slot.starts_at<now() then raise exception 'Payment captured after reservation expiry; manual refund/rebooking required';end if;
 end if;
 update public.carmitra_payment_orders set payment_id=p_payment,paid_at=now() where booking_id=p_booking and order_id=p_order and amount_paise=b.total_paise;
 if not found then raise exception 'Payment order mismatch';end if;
 update public.carmitra_bookings set payment_status='paid',status='booked',expires_at=null where id=p_booking;
 insert into public.carmitra_booking_status_logs(booking_id,user_id,status) values(b.id,b.user_id,'booked');return true;
end $$;
create function public.carmitra_mark_paid(p_booking uuid,p_order text,p_payment text) returns boolean language sql security invoker set search_path='' as $$ select carmitra_internal.mark_paid(p_booking,p_order,p_payment) $$;
revoke all on all functions in schema carmitra_internal from public,anon,authenticated;
grant execute on function carmitra_internal.quote(uuid,integer[]),carmitra_internal.available_slots(date,integer[]),carmitra_internal.create_booking(uuid,integer[],uuid,uuid,text,uuid) to authenticated;
grant usage on schema carmitra_internal to service_role;
grant execute on function carmitra_internal.mark_paid(uuid,text,text) to service_role;
revoke all on function public.carmitra_quote(uuid,integer[]),public.carmitra_available_slots(date,integer[]),public.carmitra_create_booking(uuid,integer[],uuid,uuid,text,uuid),public.carmitra_mark_paid(uuid,text,text) from public,anon,authenticated;
grant execute on function public.carmitra_quote(uuid,integer[]),public.carmitra_available_slots(date,integer[]),public.carmitra_create_booking(uuid,integer[],uuid,uuid,text,uuid) to authenticated;
grant execute on function public.carmitra_mark_paid(uuid,text,text) to service_role;
commit;
