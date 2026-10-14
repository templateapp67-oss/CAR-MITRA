begin;
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
create policy payment_server_only on public.carmitra_payment_orders for select to anon,authenticated using(false);
create policy runtime_server_only on public.carmitra_runtime_settings for select to anon,authenticated using(false);
create index on public.carmitra_addresses(locality);
create index on public.carmitra_audit_logs(actor);
create index on public.carmitra_booking_status_logs(booking_id);
create index on public.carmitra_bookings(address_id);
create index on public.carmitra_bookings(coupon_id);
create index on public.carmitra_bookings(subscription_id);
create index on public.carmitra_bookings(vehicle_id);
create index on public.carmitra_channel_applications(locality);
create index on public.carmitra_kit_requests(kit_id);
create index on public.carmitra_partner_applications(locality);
create index on public.carmitra_partners(locality);
create index on public.carmitra_user_subscriptions(plan_id);
create index on public.carmitra_vehicles(vehicle_type);
create index on public.carmitra_warranty_claims(booking_id);
-- Split ALL policies, then combine equivalent read predicates per role.
do $$declare x record;t record;r name;pred text;preds jsonb;begin
 for x in select * from pg_policies where schemaname='public' and tablename like 'carmitra_%' and cmd='ALL' loop
  execute format('drop policy %I on public.%I',x.policyname,x.tablename);
  execute format('create policy %I on public.%I for insert to authenticated with check (%s)',x.policyname||'_insert',x.tablename,coalesce(x.with_check,x.qual,'true'));
  execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)',x.policyname||'_update',x.tablename,coalesce(x.qual,'true'),coalesce(x.with_check,x.qual,'true'));
  execute format('create policy %I on public.%I for delete to authenticated using (%s)',x.policyname||'_delete',x.tablename,coalesce(x.qual,'true'));
  execute format('create policy %I on public.%I for select to authenticated using (%s)',x.policyname||'_read',x.tablename,coalesce(x.qual,'true'));
 end loop;
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'carmitra_%' loop
  preds:='{}'::jsonb;
  foreach r in array array['anon'::name,'authenticated'::name] loop
   select string_agg('('||coalesce(qual,'true')||')',' OR ') into pred from pg_policies where schemaname='public' and tablename=t.tablename and cmd='SELECT' and (r=any(roles) or 'public'::name=any(roles));
   if pred is not null then preds:=preds||jsonb_build_object(r::text,replace(pred,'carmitra_internal.is_admin()','(select carmitra_internal.is_admin())'));end if;
  end loop;
  for x in select policyname from pg_policies where schemaname='public' and tablename=t.tablename and cmd='SELECT' loop execute format('drop policy %I on public.%I',x.policyname,t.tablename);end loop;
  foreach r in array array['anon'::name,'authenticated'::name] loop if preds ? r::text then execute format('create policy %I on public.%I for select to %I using (%s)','read_'||r::text,t.tablename,r,preds->>r::text);end if;end loop;
 end loop;
end $$;
commit;
