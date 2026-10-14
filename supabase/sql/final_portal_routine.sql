create or replace function carmitra_internal.portal(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
end $$;
