begin;
create table public.carmitra_coupons(id uuid primary key default gen_random_uuid(),code text unique not null check(code=upper(trim(code))),label text not null,percent integer not null check(percent between 1 and 95),minimum_paise integer not null default 0,maximum_discount_paise integer not null check(maximum_discount_paise>0),max_uses integer not null default 100 check(max_uses>0),expires_at timestamptz not null,active boolean not null default false,created_at timestamptz not null default now());
alter table public.carmitra_coupons enable row level security;
grant select on public.carmitra_coupons to anon,authenticated;
grant insert,update,delete on public.carmitra_coupons to authenticated;
grant all on public.carmitra_coupons to service_role;
create policy coupon_public on public.carmitra_coupons for select to anon,authenticated using(active and expires_at>now());
create policy coupon_admin on public.carmitra_coupons for all to authenticated using(carmitra_internal.is_admin()) with check(carmitra_internal.is_admin());
alter table public.carmitra_bookings add column coupon_id uuid references public.carmitra_coupons(id),add column subtotal_paise integer,add column discount_paise integer not null default 0 check(discount_paise>=0);
create function carmitra_internal.discount_quote(p_vehicle uuid,p_services integer[],p_coupon text) returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb;c public.carmitra_coupons;discount integer:=0;subtotal integer;begin
 q:=carmitra_internal.quote(p_vehicle,p_services);subtotal:=(q->>'total_paise')::integer;
 if nullif(trim(p_coupon),'') is not null then
  select * into c from public.carmitra_coupons where code=upper(trim(p_coupon)) and active and expires_at>now();
  if c.id is null or subtotal<c.minimum_paise then raise exception 'Coupon is unavailable or minimum booking value is not met';end if;
  if (select count(*) from public.carmitra_bookings where coupon_id=c.id)>=c.max_uses then raise exception 'Coupon usage limit reached';end if;
  if exists(select 1 from public.carmitra_bookings where coupon_id=c.id and user_id=auth.uid()) then raise exception 'This coupon has already been used by your account';end if;
  discount:=least(round(subtotal*c.percent/100.0),c.maximum_discount_paise,subtotal-1);
 end if;
 return q||jsonb_build_object('subtotal_paise',subtotal,'discount_paise',discount,'total_paise',subtotal-discount,'coupon_id',c.id);
end $$;
create function public.carmitra_quote_with_coupon(p_vehicle uuid,p_services integer[],p_coupon text default '') returns jsonb language sql security invoker set search_path='' as $$select carmitra_internal.discount_quote(p_vehicle,p_services,p_coupon)$$;
create function carmitra_internal.create_discounted_booking(p_vehicle uuid,p_services integer[],p_address uuid,p_slot uuid,p_payment text,p_request uuid,p_coupon text) returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb;b jsonb;c uuid;u uuid:=auth.uid();begin
 if u is null then raise exception 'Sign in required';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||p_request::text,0));
 select to_jsonb(x) into b from public.carmitra_bookings x where user_id=u and request_id=p_request;if b is not null then return b;end if;
 if nullif(trim(p_coupon),'') is not null then perform 1 from public.carmitra_coupons where code=upper(trim(p_coupon)) for update;end if;
 q:=carmitra_internal.discount_quote(p_vehicle,p_services,p_coupon);
 b:=carmitra_internal.create_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request);
 update public.carmitra_bookings set total_paise=(q->>'total_paise')::integer,subtotal_paise=(q->>'subtotal_paise')::integer,discount_paise=(q->>'discount_paise')::integer,coupon_id=(q->>'coupon_id')::uuid where id=(b->>'id')::uuid;
 return (select to_jsonb(x) from public.carmitra_bookings x where id=(b->>'id')::uuid);
end $$;
create function public.carmitra_create_booking_discounted(p_vehicle uuid,p_services integer[],p_address uuid,p_slot uuid,p_payment text,p_request uuid,p_coupon text default '') returns jsonb language sql security invoker set search_path='' as $$select carmitra_internal.create_discounted_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request,p_coupon)$$;
create function carmitra_internal.reschedule(p_booking uuid,p_slot uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.carmitra_bookings;s public.carmitra_slots;used integer;begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select * into b from public.carmitra_bookings where id=p_booking and user_id=auth.uid() and status in ('booked','partner_assigned') and starts_at>now()+interval '2 hours' for update;if b.id is null then raise exception 'Rescheduling requires at least 2 hours notice before dispatch';end if;
 perform 1 from public.carmitra_slots where id in (b.slot_id,p_slot) order by id for update;
 select * into s from public.carmitra_slots where id=p_slot and active and starts_at>now()+interval '2 hours' and starts_at<now()+interval '30 days';if s.id is null or s.ends_at-s.starts_at<make_interval(mins=>b.duration_minutes) then raise exception 'Choose a supported service slot';end if;
 select count(*) into used from public.carmitra_bookings where slot_id=p_slot and id<>b.id and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());if used>=s.capacity then raise exception 'The selected slot is full';end if;
 update public.carmitra_bookings set slot_id=p_slot,starts_at=s.starts_at,partner_id=null,partner_accepted=false,status='booked' where id=b.id;
 insert into public.carmitra_booking_status_logs(booking_id,user_id,status) values(b.id,b.user_id,'rescheduled');return jsonb_build_object('rescheduled',true);
end $$;
create function public.carmitra_reschedule(p_booking uuid,p_slot uuid) returns jsonb language sql security invoker set search_path='' as $$select carmitra_internal.reschedule(p_booking,p_slot)$$;
revoke all on function carmitra_internal.discount_quote(uuid,integer[],text),public.carmitra_quote_with_coupon(uuid,integer[],text),carmitra_internal.create_discounted_booking(uuid,integer[],uuid,uuid,text,uuid,text),public.carmitra_create_booking_discounted(uuid,integer[],uuid,uuid,text,uuid,text),carmitra_internal.reschedule(uuid,uuid),public.carmitra_reschedule(uuid,uuid) from public,anon;
grant execute on function carmitra_internal.discount_quote(uuid,integer[],text),public.carmitra_quote_with_coupon(uuid,integer[],text),carmitra_internal.create_discounted_booking(uuid,integer[],uuid,uuid,text,uuid,text),public.carmitra_create_booking_discounted(uuid,integer[],uuid,uuid,text,uuid,text),carmitra_internal.reschedule(uuid,uuid),public.carmitra_reschedule(uuid,uuid) to authenticated;
commit;
