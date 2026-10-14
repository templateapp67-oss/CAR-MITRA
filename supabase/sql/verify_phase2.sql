-- Read-only checks, run after setup and catalogue in the selected CarMitra project.
select tablename, rowsecurity from pg_tables where schemaname='public' and tablename like 'carmitra_%' order by tablename;
select count(*) as services, count(*) filter(where price_paise is null) as unpriced_services from public.carmitra_services;
select count(*) as configured_jaipur_localities from public.carmitra_areas;
select has_table_privilege('authenticated','public.carmitra_bookings','INSERT') as client_booking_insert_must_be_false,has_table_privilege('authenticated','public.carmitra_payment_orders','UPDATE') as client_payment_update_must_be_false,has_function_privilege('authenticated','public.carmitra_mark_paid(uuid,text,text)','EXECUTE') as client_mark_paid_must_be_false;
select n.nspname,p.proname,p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like 'carmitra_%' or n.nspname='carmitra_internal' order by 1,2;
