-- Jaipur locality selection; no fabricated slots or availability.
insert into public.carmitra_areas(locality,active) values
('Vaishali Nagar',true),('C-Scheme',true),('Civil Lines',true),('Bani Park',true),('Malviya Nagar',true),('Mansarovar',true),('Raja Park',true),('Jagatpura',true),('Shyam Nagar',true),('Tonk Road',true)
on conflict(locality) do nothing;
