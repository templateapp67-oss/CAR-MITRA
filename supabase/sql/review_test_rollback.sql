-- Transactional fixtures: all accounts, bookings and storage metadata are rolled back.
begin;
insert into auth.users(id,email) values('00000000-0000-4000-a000-000000000001','carmitra-transaction-test-1@example.invalid'),('00000000-0000-4000-a000-000000000002','carmitra-transaction-test-2@example.invalid'),('00000000-0000-4000-a000-000000000003','carmitra-transaction-partner@example.invalid'),('00000000-0000-4000-a000-000000000004','carmitra-transaction-admin@example.invalid');
insert into public.carmitra_user_roles values('00000000-0000-4000-a000-000000000004','admin');
insert into public.carmitra_vehicles(id,user_id,vehicle_type,brand,model,registration,fuel) values('10000000-0000-4000-a000-000000000001','00000000-0000-4000-a000-000000000001','hatchback','Test','Vehicle','RJ14TEST1','Petrol'),('10000000-0000-4000-a000-000000000002','00000000-0000-4000-a000-000000000002','hatchback','Test','Vehicle','RJ14TEST2','Petrol');
insert into public.carmitra_addresses(id,user_id,label,line1,locality,pin_code,contact_phone) values('20000000-0000-4000-a000-000000000001','00000000-0000-4000-a000-000000000001','Test','Transaction-only address','Vaishali Nagar','302021','9000000001'),('20000000-0000-4000-a000-000000000002','00000000-0000-4000-a000-000000000002','Test','Transaction-only address','Vaishali Nagar','302021','9000000002');
insert into public.carmitra_slots(id,starts_at,ends_at,capacity) values('30000000-0000-4000-a000-000000000001',now()+interval '40 minutes',now()+interval '7 hours',1),('30000000-0000-4000-a000-000000000002',now()+interval '3 days',now()+interval '3 days 7 hours',1),('30000000-0000-4000-a000-000000000003',now()+interval '4 days',now()+interval '4 days 7 hours',1);
do $$declare b jsonb;service integer;blocked boolean;begin
perform set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000001',true);
select id into service from public.carmitra_services where active and is_package order by price_paise limit 1;
b:=public.carmitra_create_booking_discounted('10000000-0000-4000-a000-000000000001',array[service],'20000000-0000-4000-a000-000000000001','30000000-0000-4000-a000-000000000001','cash',gen_random_uuid(),'');
perform set_config('carmitra.test_booking',b->>'id',true);
blocked:=false;begin perform public.carmitra_save_review((b->>'id')::uuid,'Fixture',5,'Pending service cannot receive a review.');exception when others then blocked:=true;end;if not blocked then raise exception 'Pending booking review allowed';end if;
update public.carmitra_bookings set status='completed',completed_at=now() where id=(b->>'id')::uuid;
end $$;
set local role authenticated;
do $$declare b uuid:=current_setting('carmitra.test_booking')::uuid;r jsonb;rid uuid;blocked boolean;begin
perform set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000001',true);
r:=public.carmitra_save_review(b,'Review fixture',4,'An updated verified review in this transaction.');
perform public.carmitra_save_review(b,'Review fixture',4,'An updated verified review in this transaction.');
if (select count(*)from public.carmitra_reviews where booking_id=b)<>1 then raise exception 'Review edit duplicated rating';end if;
select id into rid from public.carmitra_reviews where booking_id=b;
r:=public.carmitra_review_feed(1,4,'newest','updated');if (r->>'matching')::integer<>1 or jsonb_array_length(r->'items')<>1 then raise exception 'Review filter failed';end if;
if (r->'items'->0) ? 'user_id' or (r->'items'->0) ? 'booking_id' then raise exception 'Public feed leaks ownership';end if;
blocked:=false;begin perform public.carmitra_save_review(b,'Review fixture',6,'Invalid rating must be rejected.');exception when others then blocked:=true;end;if not blocked then raise exception 'Invalid rating allowed';end if;
perform set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000004',true);
perform public.carmitra_portal('moderate_review',jsonb_build_object('id',rid,'published',false));
perform set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000001',true);
r:=public.carmitra_save_review(b,'Review fixture',5,'Editing a hidden review must not republish it.');if (r->>'published')::boolean then raise exception 'Moderation bypassed';end if;
perform set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000002',true);
blocked:=false;begin perform public.carmitra_save_review(b,'Other user',5,'Unauthorized edit must be rejected.');exception when others then blocked:=true;end;if not blocked then raise exception 'Cross-account review edit allowed';end if;
perform set_config('request.jwt.claim.sub','',true);
blocked:=false;begin perform public.carmitra_save_review(b,'Anonymous',5,'Anonymous review must be rejected.');exception when others then blocked:=true;end;if not blocked then raise exception 'Anonymous review allowed';end if;
if has_function_privilege('anon','public.carmitra_save_review(uuid,text,integer,text)','execute') then raise exception 'Anonymous write permission';end if;
end $$;
rollback;
select 'PASS: real server booking, pending-service gate, review save/edit, one review per booking, rating/search filter, privacy, preserved moderation, cross-account and anonymous rejection; fixtures rolled back' as result;
