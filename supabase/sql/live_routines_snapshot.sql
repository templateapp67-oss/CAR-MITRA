-- Current hosted routines. Apply only after schema initialization and grants; CREATE OR REPLACE preserves existing ACLs.

CREATE OR REPLACE FUNCTION carmitra_internal.available_slots(p_date date, p_services integer[])
 RETURNS TABLE(id uuid, starts_at timestamp with time zone, remaining integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d integer;n integer;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select count(*),sum(duration_minutes) into n,d from public.carmitra_services where id=any(p_services) and active and price_paise is not null;
 if n<>cardinality(p_services) or d is null then raise exception 'Select available services';end if;
 return query select s.id,s.starts_at,(s.capacity-count(b.id))::integer from public.carmitra_slots s left join public.carmitra_bookings b on b.slot_id=s.id and b.status<>'cancelled' and (b.status<>'awaiting_payment' or b.expires_at>now()) where s.active and (s.starts_at at time zone 'Asia/Kolkata')::date=p_date and s.starts_at>now()+interval '30 minutes' and s.starts_at<now()+interval '30 days' and s.ends_at-s.starts_at>=make_interval(mins=>d) group by s.id having count(b.id)<s.capacity order by s.starts_at;
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.create_booking(p_vehicle uuid, p_services integer[], p_address uuid, p_slot uuid, p_payment text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid();q jsonb;s public.carmitra_slots;a public.carmitra_addresses;v public.carmitra_vehicles;existing public.carmitra_bookings;b public.carmitra_bookings;used integer;items jsonb;
begin
 if u is null then raise exception 'Sign in required';end if;
 if p_request is null or p_payment is null or p_payment not in ('cash','razorpay') then raise exception 'Invalid booking request';end if;
 if p_payment='razorpay' and not coalesce((select online_test_enabled from public.carmitra_runtime_settings where id=true),false) then raise exception 'Online payment is not configured yet';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||p_request::text,0));
 select * into existing from public.carmitra_bookings where user_id=u and request_id=p_request;
 if existing.id is not null then return to_jsonb(existing);end if;
 if (select count(*) from public.carmitra_bookings where user_id=u and created_at>now()-interval '1 hour')>=10 then raise exception 'Booking limit reached. Please try later';end if;
 perform 1 from public.carmitra_services where id=any(p_services) order by id for share; perform 1 from public.carmitra_vehicle_multipliers where vehicle_type=(select vehicle_type from public.carmitra_vehicles where id=p_vehicle and user_id=u) for share; q:=carmitra_internal.quote(p_vehicle,p_services);
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
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.create_discounted_booking(p_vehicle uuid, p_services integer[], p_address uuid, p_slot uuid, p_payment text, p_request uuid, p_coupon text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q jsonb;b jsonb;c uuid;u uuid:=auth.uid();begin
 if u is null then raise exception 'Sign in required';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text||p_request::text,0));
 select to_jsonb(x) into b from public.carmitra_bookings x where user_id=u and request_id=p_request;if b is not null then return b;end if;
 if nullif(trim(p_coupon),'') is not null then perform 1 from public.carmitra_coupons where code=upper(trim(p_coupon)) for update;end if;
 perform 1 from public.carmitra_services where id=any(p_services) order by id for share; perform 1 from public.carmitra_vehicle_multipliers where vehicle_type=(select vehicle_type from public.carmitra_vehicles where id=p_vehicle and user_id=u) for share; q:=carmitra_internal.discount_quote(p_vehicle,p_services,p_coupon);
 b:=carmitra_internal.create_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request);
 update public.carmitra_bookings set total_paise=(q->>'total_paise')::integer,subtotal_paise=(q->>'subtotal_paise')::integer,discount_paise=(q->>'discount_paise')::integer,coupon_id=(q->>'coupon_id')::uuid where id=(b->>'id')::uuid;
 return (select to_jsonb(x) from public.carmitra_bookings x where id=(b->>'id')::uuid);
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.create_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin insert into public.carmitra_profiles(user_id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')) on conflict(user_id) do nothing;return new;end$function$;

CREATE OR REPLACE FUNCTION carmitra_internal.discount_quote(p_vehicle uuid, p_services integer[], p_coupon text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.distance_km(a double precision, b double precision, c double precision, d double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$select 6371*acos(least(1.0,greatest(-1.0,sin(radians(a))*sin(radians(c))+cos(radians(a))*cos(radians(c))*cos(radians(d-b)))))$function$;

CREATE OR REPLACE FUNCTION carmitra_internal.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select auth.uid() is not null and exists(select 1 from public.carmitra_user_roles where user_id=auth.uid() and role='admin') $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.mark_paid(p_booking uuid, p_order text, p_payment text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.media_access(path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select auth.uid() is not null and (carmitra_internal.is_admin() or exists(select 1 from public.carmitra_bookings b where b.id::text=split_part(path,'/',2) and (b.user_id=auth.uid() or b.partner_id=auth.uid())))$function$;

CREATE OR REPLACE FUNCTION carmitra_internal.operations(op text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.portal(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid();admin boolean;app public.carmitra_partner_applications;ca public.carmitra_channel_applications;b public.carmitra_bookings;partner public.carmitra_partners;s public.carmitra_site_settings;jc carmitra_internal.job_codes;balance bigint;amount integer;fee integer;refund integer;sub public.carmitra_user_subscriptions;plan public.carmitra_subscription_plans;r public.carmitra_payout_requests;result jsonb;doc text;otp text;bytes bytea;bid uuid;ps uuid;req uuid;
begin
 if u is null then raise exception 'Sign in required';end if;admin:=carmitra_internal.is_admin();select * into s from public.carmitra_site_settings where id=true;
 if action='partner_for_booking' then select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u;if b.id is null then raise exception 'Booking not found';end if;return (select jsonb_build_object('full_name',full_name,'phone',phone) from public.carmitra_partners where user_id=b.partner_id);end if;
 if action='notifications' then return coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.carmitra_notifications n where user_id=u),'[]'::jsonb);end if;
 if action='mark_notifications' then update public.carmitra_notifications set read_at=now() where user_id=u and read_at is null;return jsonb_build_object('saved',true);end if;
 if action='identity' then return jsonb_build_object('user_id',u,'admin',admin,'partner',exists(select 1 from public.carmitra_partners where user_id=u and active),'channel',exists(select 1 from public.carmitra_channel_partners where user_id=u and active));end if;
 if action='apply_partner' then
  if (p->>'full_name') is null or length(trim(p->>'full_name'))<2 or (p->>'email') !~ '^[^ ]+@[^ ]+\.[^ ]+$' then raise exception 'Enter your name and email';end if;
  foreach doc in array array['identity','photo','police'] loop
   if (p->'documents'->>doc) is null or (p->'documents'->>doc) not like u::text||'/%' or not exists(select 1 from storage.objects where bucket_id='carmitra-documents' and name=p->'documents'->>doc) then raise exception 'Upload identity, photo and police verification documents';end if;
  end loop;
  insert into public.carmitra_partner_applications(user_id,full_name,phone,email,locality,experience,skills,equipment,documents) values(u,trim(p->>'full_name'),p->>'phone',p->>'email',p->>'locality',(p->>'experience')::integer,array(select jsonb_array_elements_text(p->'skills')::integer),(p->>'equipment')::boolean,p->'documents') on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,email=excluded.email,locality=excluded.locality,experience=excluded.experience,skills=excluded.skills,equipment=excluded.equipment,documents=excluded.documents,status='pending',review_note='' where carmitra_partner_applications.status='rejected' returning * into app;
  if app.id is null then raise exception 'An application already exists. Check your partner dashboard';end if;return to_jsonb(app);
 elsif action='apply_channel' then
  if length(trim(p->>'full_name'))<2 then raise exception 'Enter your name';end if;
  insert into public.carmitra_channel_applications(user_id,full_name,phone,tier,locality,experience) values(u,p->>'full_name',p->>'phone',p->>'tier',p->>'locality',coalesce(p->>'experience','')) returning * into ca;return to_jsonb(ca);
 elsif action='sign_agreement' then
  if coalesce((p->>'accept')::boolean,false) is not true then raise exception 'Accept the partner agreement';end if;
  update public.carmitra_partners set agreement_signed_at=now(),agreement_version=s.agreement_version where user_id=u and active returning * into partner;if partner.user_id is null then raise exception 'Approved partner access required';end if;return jsonb_build_object('signed',true);
 elsif action='partner_dashboard' then
  select * into partner from public.carmitra_partners where user_id=u;
  return jsonb_build_object('partner',to_jsonb(partner),'application',(select to_jsonb(a) from public.carmitra_partner_applications a where user_id=u),'jobs',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from public.carmitra_bookings x where partner_id=u),'[]'::jsonb),'wallet',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.carmitra_wallet_transactions x where user_id=u),'[]'::jsonb),'balance_paise',coalesce((select sum(amount_paise) from public.carmitra_wallet_transactions where user_id=u and kind<>'cash_earning'),0),'payouts',coalesce((select jsonb_agg(to_jsonb(x)) from public.carmitra_payout_requests x where user_id=u),'[]'::jsonb));
 elsif action='channel_dashboard' then
  return jsonb_build_object('profile',(select to_jsonb(c) from public.carmitra_channel_partners c where user_id=u),'application',(select to_jsonb(c) from public.carmitra_channel_applications c where user_id=u),'leads',coalesce((select jsonb_agg(jsonb_build_object('id',bk.id,'starts_at',bk.starts_at,'status',bk.status,'locality',bk.address_snapshot->>'locality','services',bk.service_snapshot)) from public.carmitra_bookings bk where exists(select 1 from public.carmitra_channel_partners c where c.user_id=u and c.active and c.tier in ('zone','city') and bk.address_snapshot->>'locality'=any(c.localities))),'[]'::jsonb));
 elsif action='request_payout' then
  if not exists(select 1 from public.carmitra_partners where user_id=u and active and agreement_signed_at is not null) then raise exception 'Verified partner required';end if;
  perform pg_advisory_xact_lock(hashtextextended(u::text,0));amount:=(p->>'amount_paise')::integer;
  select coalesce(sum(amount_paise),0) into balance from public.carmitra_wallet_transactions where user_id=u and kind<>'cash_earning';
  if amount is null or amount<=0 or amount>balance or (p->>'upi') !~ '^[a-zA-Z0-9._-]+@[a-zA-Z0-9]+$' then raise exception 'Enter a valid amount within your available wallet balance and UPI ID';end if;
  insert into public.carmitra_payout_requests(user_id,amount_paise,upi) values(u,amount,p->>'upi') returning * into r;
  insert into public.carmitra_wallet_transactions(user_id,kind,amount_paise) values(u,'withdrawal_reserved',-amount);return to_jsonb(r);
 elsif action='job_code' then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u and status in ('partner_assigned','on_the_way');if b.id is null then raise exception 'No assigned booking found';end if;
  select * into jc from carmitra_internal.job_codes where booking_id=b.id;
  if jc.booking_id is null or jc.expires_at<now() then bytes:=extensions.gen_random_bytes(3);otp:=((get_byte(bytes,0)*65536+get_byte(bytes,1)*256+get_byte(bytes,2))%900000+100000)::text;insert into carmitra_internal.job_codes values(b.id,otp,now()+interval '15 minutes',0) on conflict(booking_id) do update set code=excluded.code,expires_at=excluded.expires_at,attempts=0 returning * into jc;end if;
  return jsonb_build_object('code',jc.code,'expires_at',jc.expires_at);
 elsif action='customer_signature' then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u and status='started' for update;
  doc:=p->>'path';if b.id is null or doc not like u::text||'/'||b.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='carmitra-job-media' and name=doc) then raise exception 'Upload your completion signature for this active booking';end if;
  update public.carmitra_bookings set customer_signature=doc where id=b.id;return jsonb_build_object('saved',true);
 elsif action='job_action' then
  select * into partner from public.carmitra_partners where user_id=u and active and agreement_signed_at is not null;if partner.user_id is null then raise exception 'Approved partner and signed agreement required';end if;
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and partner_id=u for update;if b.id is null then raise exception 'Assigned booking not found';end if;
  if p->>'operation'='accept' and b.status='partner_assigned' then update public.carmitra_bookings set partner_accepted=true where id=b.id;
  elsif p->>'operation'='reject' and b.status='partner_assigned' then update public.carmitra_bookings set partner_id=null,partner_accepted=false,status='booked' where id=b.id;
  elsif p->>'operation'='on_the_way' and b.status='partner_assigned' and b.partner_accepted then update public.carmitra_bookings set status='on_the_way' where id=b.id;
  elsif p->>'operation'='start' and b.status='on_the_way' and b.partner_accepted then
   if b.starts_at>now()+interval '45 minutes' then raise exception 'The service time has not arrived yet';end if;
   select * into jc from carmitra_internal.job_codes where booking_id=b.id for update;
   if jc.booking_id is null or jc.expires_at<now() or jc.attempts>=5 then return jsonb_build_object('error','Ask the customer for a fresh job-start code');end if;
   if jc.code is distinct from p->>'otp' then update carmitra_internal.job_codes set attempts=attempts+1 where booking_id=b.id;return jsonb_build_object('error','Incorrect job-start code');end if;
   doc:=p->>'path';if doc is null or doc not like u::text||'/'||b.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='carmitra-job-media' and name=doc) then raise exception 'Upload a before photo';end if;
   update public.carmitra_bookings set status='started',before_photo=doc where id=b.id;delete from carmitra_internal.job_codes where booking_id=b.id;
  elsif p->>'operation'='complete' and b.status='started' then
   doc:=p->>'path';if doc is null or doc not like u::text||'/'||b.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='carmitra-job-media' and name=doc) then raise exception 'Upload an after photo';end if;
   if b.customer_signature is null then raise exception 'Customer must confirm completion with a signature first';end if;
   if b.payment_method='cash' and coalesce((p->>'cash_collected')::boolean,false) is not true then raise exception 'Confirm cash collection';end if;
   if b.payment_method<>'cash' and b.payment_status<>'paid' then raise exception 'Payment must be verified before completion';end if;
   update public.carmitra_bookings set status='completed',after_photo=doc,completed_at=now(),payment_status=case when payment_method='cash' then 'cash_collected' else payment_status end where id=b.id;
   amount:=round(b.total_paise*0.9);
   insert into public.carmitra_wallet_transactions(user_id,booking_id,kind,amount_paise) values(u,b.id,case when b.payment_method='cash' then 'cash_earning' else 'online_earning' end,amount);
   if b.payment_method='cash' then insert into public.carmitra_wallet_transactions(user_id,booking_id,kind,amount_paise) values(u,b.id,'cash_platform_due',-(b.total_paise-amount));end if;
  else raise exception 'This job action is not valid in the current status';end if;
  insert into public.carmitra_booking_status_logs(booking_id,user_id,status) select id,user_id,status from public.carmitra_bookings where id=b.id;return jsonb_build_object('updated',true);
 elsif action in ('cancel_quote','cancel') then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u for update;if b.id is null or b.status in ('completed','cancelled') then raise exception 'This booking cannot be cancelled';end if;
  fee:=case when b.status='started' then b.total_paise when b.status='on_the_way' then round(b.total_paise*0.5) when b.starts_at<now()+interval '2 hours' then round(b.total_paise*s.late_cancellation_percent/100.0) else 0 end;
  refund:=case when b.payment_status='paid' and b.payment_method='razorpay' then b.total_paise-fee else 0 end;
  if action='cancel' and ((p->>'expected_fee_paise')::integer is distinct from fee) then raise exception 'Cancellation charge changed. Please review the policy again';end if;
  if action='cancel_quote' then return jsonb_build_object('total_paise',b.total_paise,'fee_paise',fee,'refund_paise',refund,'membership_restore',b.payment_method='membership' and fee=0,'policy',case when b.status='started' then '100% charge: service started' when b.status='on_the_way' then '50% charge: partner dispatched' when b.starts_at>=now()+interval '2 hours' then 'Free cancellation: at least 2 hours before service' else 'Pre-dispatch cancellation per configured policy' end);end if;
  if length(trim(coalesce(p->>'reason','')))<3 then raise exception 'Choose a cancellation reason';end if;
  if b.subscription_id is not null and fee=0 then update public.carmitra_user_subscriptions set washes_left=washes_left+1 where id=b.subscription_id;end if;
  insert into public.carmitra_cancellation_requests(booking_id,user_id,reason,fee_paise,refund_paise,status) values(b.id,u,p->>'reason',fee,refund,case when refund>0 then 'pending' else 'no_refund' end);
  update public.carmitra_bookings set status='cancelled',payment_status=case when refund>0 then 'refund_pending' else payment_status end where id=b.id;
  insert into public.carmitra_booking_status_logs(booking_id,user_id,status) values(b.id,u,'cancelled');return jsonb_build_object('cancelled',true,'refund_pending',refund>0,'cash_fee_due_paise',case when b.payment_method='cash' then fee else 0 end);
 elsif action='review' then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u and status='completed';if b.id is null then raise exception 'Reviews require a completed booking';end if;
  insert into public.carmitra_reviews(booking_id,user_id,display_name,rating,body) values(b.id,u,p->>'display_name',(p->>'rating')::integer,p->>'body');return jsonb_build_object('saved',true);
 elsif action='warranty' then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and user_id=u and status='completed' and completed_at>=now()-interval '7 days';if b.id is null then raise exception 'Warranty requests must be within 7 days of completion';end if;
  if length(trim(p->>'description'))<10 then raise exception 'Describe the issue in at least 10 characters';end if;
  insert into public.carmitra_warranty_claims(booking_id,user_id,description) values(b.id,u,p->>'description');return jsonb_build_object('saved',true);
 elsif action='request_subscription' then
  select * into plan from public.carmitra_subscription_plans where id=(p->>'plan_id')::uuid and active;if plan.id is null then raise exception 'Plan unavailable';end if;
  if exists(select 1 from public.carmitra_user_subscriptions where user_id=u and plan_id=plan.id and status='requested') then raise exception 'A membership request already exists';end if;
  insert into public.carmitra_user_subscriptions(user_id,plan_id) values(u,plan.id);return jsonb_build_object('requested',true);
 elsif action='redeem_subscription' then
  select * into sub from public.carmitra_user_subscriptions where id=(p->>'subscription_id')::uuid and user_id=u and status='active' and expires_at>now() for update;if sub.id is null or sub.washes_left<=0 then raise exception 'No active washes remaining';end if;
  req:=(p->>'request_id')::uuid;
  select to_jsonb(x) into result from public.carmitra_bookings x where user_id=u and request_id=req;if result is not null then return result;end if;
  select * into plan from public.carmitra_subscription_plans where id=sub.plan_id;
  result:=carmitra_internal.create_booking((p->>'vehicle_id')::uuid,array[1],(p->>'address_id')::uuid,(p->>'slot_id')::uuid,'cash',req);bid:=(result->>'id')::uuid;
  update public.carmitra_bookings set payment_method='membership',payment_status='paid',total_paise=round(sub.paid_price_paise/sub.included_washes::numeric),subscription_id=sub.id where id=bid;
  update public.carmitra_user_subscriptions set washes_left=washes_left-1 where id=sub.id;
  return (select to_jsonb(x) from public.carmitra_bookings x where id=bid);
 elsif action='request_kit' then
  if not exists(select 1 from public.carmitra_kits where id=(p->>'kit_id')::uuid and active) then raise exception 'Kit unavailable';end if;
  insert into public.carmitra_kit_requests(user_id,kit_id,note) values(u,(p->>'kit_id')::uuid,coalesce(p->>'note',''));return jsonb_build_object('requested',true);
 end if;
 if not admin then raise exception 'Admin access required';end if;
 if action='admin_overview' then return jsonb_build_object('bookings',(select count(*) from public.carmitra_bookings),'completed',(select count(*) from public.carmitra_bookings where status='completed'),'revenue_paise',(select coalesce(sum(total_paise),0) from public.carmitra_bookings where status='completed'),'partners',(select count(*) from public.carmitra_partners where active),'pending_applications',(select count(*) from public.carmitra_partner_applications where status='pending'),'pending_payouts',(select count(*) from public.carmitra_payout_requests where status='pending'));
 elsif action='review_partner' then
  select * into app from public.carmitra_partner_applications where id=(p->>'id')::uuid for update;if app.id is null then raise exception 'Application not found';end if;
  update public.carmitra_partner_applications set status=p->>'status',review_note=coalesce(p->>'note','') where id=app.id;
  if p->>'status'='approved' then insert into public.carmitra_partners(user_id,application_id,full_name,phone,locality,skills) values(app.user_id,app.id,app.full_name,app.phone,app.locality,app.skills) on conflict(user_id) do update set active=true,locality=excluded.locality,skills=excluded.skills;else update public.carmitra_partners set active=false where user_id=app.user_id;end if;
  insert into public.carmitra_notifications(user_id,message) values(app.user_id,'Partner application: '||(p->>'status'));
 elsif action='review_channel' then
  select * into ca from public.carmitra_channel_applications where id=(p->>'id')::uuid for update;if ca.id is null then raise exception 'Application not found';end if;
  update public.carmitra_channel_applications set status=p->>'status',review_note=coalesce(p->>'note','') where id=ca.id;
  if p->>'status'='approved' then insert into public.carmitra_channel_partners(user_id,application_id,full_name,tier,localities) values(ca.user_id,ca.id,ca.full_name,ca.tier,case when ca.tier='city' then array(select locality from public.carmitra_areas where active) else array[ca.locality] end) on conflict(user_id) do update set active=true;else update public.carmitra_channel_partners set active=false where user_id=ca.user_id;end if;
 elsif action='assign_booking' then
  select * into b from public.carmitra_bookings where id=(p->>'booking_id')::uuid and status in ('booked','partner_assigned') for update;select * into partner from public.carmitra_partners where user_id=(p->>'partner_id')::uuid and active and agreement_signed_at is not null for update;
  if b.id is null or partner.user_id is null or partner.locality<>b.address_snapshot->>'locality' or exists(select 1 from public.carmitra_services x where x.id=any(b.service_ids) and not x.category=any(partner.skills)) then raise exception 'Choose an approved, available partner with matching area and skills';end if;
  if exists(select 1 from public.carmitra_bookings x where x.partner_id=partner.user_id and x.id<>b.id and x.status not in ('cancelled','completed') and tstzrange(x.starts_at,x.starts_at+make_interval(mins=>x.duration_minutes),'[)')&&tstzrange(b.starts_at,b.starts_at+make_interval(mins=>b.duration_minutes),'[)')) then raise exception 'Partner already has an overlapping job';end if;
  update public.carmitra_bookings set partner_id=partner.user_id,status='partner_assigned',partner_accepted=false where id=b.id;insert into public.carmitra_notifications(user_id,message) values(partner.user_id,'New Jaipur job assigned');
 elsif action='review_payout' then
  select * into r from public.carmitra_payout_requests where id=(p->>'id')::uuid and status='pending' for update;if r.id is null then raise exception 'Pending payout not found';end if;
  if p->>'status'='paid' and length(trim(coalesce(p->>'reference','')))<4 then raise exception 'Enter the real bank/UPI transfer reference';end if;
  if p->>'status' not in ('paid','rejected') then raise exception 'Invalid payout status';end if;
  update public.carmitra_payout_requests set status=p->>'status',reference=p->>'reference' where id=r.id;
  if p->>'status'='rejected' then insert into public.carmitra_wallet_transactions(user_id,kind,amount_paise) values(r.user_id,'withdrawal_released',r.amount_paise);end if;
 elsif action='activate_subscription' then
  select * into sub from public.carmitra_user_subscriptions where id=(p->>'id')::uuid and status='requested' for update;if sub.id is null or length(trim(coalesce(p->>'payment_reference','')))<4 then raise exception 'Record a verified payment reference before activation';end if;
  select * into plan from public.carmitra_subscription_plans where id=sub.plan_id;update public.carmitra_user_subscriptions set washes_left=plan.washes,paid_price_paise=plan.price_paise,included_washes=plan.washes,status='active',expires_at=now()+make_interval(days=>plan.valid_days) where id=sub.id;
 elsif action='moderate_review' then update public.carmitra_reviews set published=(p->>'published')::boolean where id=(p->>'id')::uuid;
 elsif action='resolve_warranty' then update public.carmitra_warranty_claims set status=p->>'status' where id=(p->>'id')::uuid;
 else raise exception 'Unknown action';end if;
 insert into public.carmitra_audit_logs(actor,action,payload) values(u,action,p);return jsonb_build_object('updated',true);
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.public_reviews()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select coalesce(jsonb_agg(jsonb_build_object('display_name',display_name,'rating',rating,'body',body,'created_at',created_at)),'[]'::jsonb) from public.carmitra_reviews where published $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.quote(p_vehicle uuid, p_services integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.reschedule(p_booking uuid, p_slot uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b public.carmitra_bookings;s public.carmitra_slots;used integer;begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select * into b from public.carmitra_bookings where id=p_booking and user_id=auth.uid() and status in ('booked','partner_assigned') and starts_at>now()+interval '2 hours' for update;if b.id is null then raise exception 'Rescheduling requires at least 2 hours notice before dispatch';end if;
 perform 1 from public.carmitra_slots where id in (b.slot_id,p_slot) order by id for update;
 select * into s from public.carmitra_slots where id=p_slot and active and starts_at>now()+interval '2 hours' and starts_at<now()+interval '30 days';if s.id is null or s.ends_at-s.starts_at<make_interval(mins=>b.duration_minutes) then raise exception 'Choose a supported service slot';end if;
 select count(*) into used from public.carmitra_bookings where slot_id=p_slot and id<>b.id and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());if used>=s.capacity then raise exception 'The selected slot is full';end if;
 update public.carmitra_bookings set slot_id=p_slot,starts_at=s.starts_at,partner_id=null,partner_accepted=false,status='booked' where id=b.id;
 insert into public.carmitra_booking_status_logs(booking_id,user_id,status) values(b.id,b.user_id,'rescheduled');return jsonb_build_object('rescheduled',true);
end $function$;

CREATE OR REPLACE FUNCTION carmitra_internal.slot_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare reserved integer;begin
 select count(*) into reserved from public.carmitra_bookings where slot_id=old.id and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());
 if reserved>0 and (new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at) then raise exception 'This slot has bookings. Create a new time window instead';end if;
 if new.capacity<reserved then raise exception 'Capacity cannot be lower than existing reservations';end if;return new;end$function$;

CREATE OR REPLACE FUNCTION public.carmitra_available_slots(p_date date, p_services integer[])
 RETURNS TABLE(id uuid, starts_at timestamp with time zone, remaining integer)
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select * from carmitra_internal.available_slots(p_date,p_services) $function$;

CREATE OR REPLACE FUNCTION public.carmitra_create_booking(p_vehicle uuid, p_services integer[], p_address uuid, p_slot uuid, p_payment text, p_request uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select carmitra_internal.create_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request) $function$;

CREATE OR REPLACE FUNCTION public.carmitra_create_booking_discounted(p_vehicle uuid, p_services integer[], p_address uuid, p_slot uuid, p_payment text, p_request uuid, p_coupon text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.create_discounted_booking(p_vehicle,p_services,p_address,p_slot,p_payment,p_request,p_coupon)$function$;

CREATE OR REPLACE FUNCTION public.carmitra_mark_paid(p_booking uuid, p_order text, p_payment text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select carmitra_internal.mark_paid(p_booking,p_order,p_payment) $function$;

CREATE OR REPLACE FUNCTION public.carmitra_operations(op text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.operations(op,p)$function$;

CREATE OR REPLACE FUNCTION public.carmitra_portal(action text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.portal(action,p)$function$;

CREATE OR REPLACE FUNCTION public.carmitra_public_reviews()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.public_reviews()$function$;

CREATE OR REPLACE FUNCTION public.carmitra_quote(p_vehicle uuid, p_services integer[])
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select carmitra_internal.quote(p_vehicle,p_services) $function$;

CREATE OR REPLACE FUNCTION public.carmitra_quote_with_coupon(p_vehicle uuid, p_services integer[], p_coupon text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.discount_quote(p_vehicle,p_services,p_coupon)$function$;

CREATE OR REPLACE FUNCTION public.carmitra_reschedule(p_booking uuid, p_slot uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select carmitra_internal.reschedule(p_booking,p_slot)$function$;

