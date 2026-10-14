begin;
alter table public.carmitra_addresses add column if not exists address_type text not null default 'home' check(address_type in ('home','work','other'));
alter table public.carmitra_addresses add column if not exists floor text not null default '' check(length(floor)<=60);
alter table public.carmitra_addresses add column if not exists landmark text not null default '' check(length(landmark)<=200);
alter table public.carmitra_addresses add column if not exists instructions text not null default '' check(length(instructions)<=500);
alter table public.carmitra_addresses add column if not exists selected_address text not null default '' check(length(selected_address)<=500);
alter table public.carmitra_services add column if not exists is_package boolean not null default false;
alter table public.carmitra_services add column if not exists inclusions text[] not null default '{}';
alter table public.carmitra_services add column if not exists description text not null default '';
insert into public.carmitra_services(id,name,category,price_paise,duration_minutes,is_package,inclusions,description)
select coalesce((select max(id) from public.carmitra_services),0)+x.n,x.name,x.category,x.price,x.minutes,true,x.inclusions,x.description from (values
 (1,'Bucket Wash - Basic',0,24900,30,array['Exterior wash','Tyre polish'],'A simple doorstep exterior clean and tyre finish.'),
 (2,'Pressure Wash - Premium',0,49900,60,array['Exterior pressure wash','Tyre polish'],'A thorough exterior wash with professional equipment.'),
 (3,'360 Deep Cleaning',3,99900,120,array['Interior vacuum','Roof cleaning','Seat cleaning'],'A deeper interior refresh for your car.')
) as x(n,name,category,price,minutes,inclusions,description) where not exists(select 1 from public.carmitra_services s where s.name=x.name);
notify pgrst,'reload schema';
commit;
