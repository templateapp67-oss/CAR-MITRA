begin;
lock table public.carmitra_services in share row exclusive mode;
update public.carmitra_services set name='Car Exterior Wash',price_paise=19900 where name='Basic Exterior Wash';
update public.carmitra_services set name='Interior Deep Clean',price_paise=49900,category=3 where name='Deep Interior Detailing';
update public.carmitra_services set name='Ceramic Coating',price_paise=299900 where name='Ceramic Coating (1 Year)';
update public.carmitra_services set price_paise=6900,duration_minutes=coalesce(duration_minutes,30) where name='Bike Wash';
insert into public.carmitra_services(id,name,category,price_paise,duration_minutes)
select (select coalesce(max(id),0)+1 from public.carmitra_services),'Waterless Eco-Wash',0,29900,30
where not exists(select 1 from public.carmitra_services where name='Waterless Eco-Wash');
insert into public.carmitra_services(id,name,category,price_paise,duration_minutes)
select (select coalesce(max(id),0)+1 from public.carmitra_services),'Tyre Polish',1,4900,15
where not exists(select 1 from public.carmitra_services where name='Tyre Polish');
update public.carmitra_site_settings set support_email='support@carmitra.in',address='Jaipur, Rajasthan (Phase-1)' where id=true;
commit;
