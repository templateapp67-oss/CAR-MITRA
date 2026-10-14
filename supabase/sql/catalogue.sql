-- Real supplied catalogue. No demo bookings, reviews or invented slots.
begin;
insert into public.carmitra_vehicle_multipliers(vehicle_type,basis_points) values ('hatchback',10000),('sedan',10000),('suv',10000),('bike',10000);
insert into public.carmitra_areas(locality) values ('Vaishali Nagar'),('Mansarovar'),('Malviya Nagar'),('Jagatpura'),('C-Scheme'),('Raja Park'),('Tonk Road');
insert into public.carmitra_services(id,name,category,price_paise,duration_minutes) values
(1,'Basic Exterior Wash',0,29900,30),
(2,'Premium Wash + Interior',0,59900,60),
(3,'Foam Wash + Wax',0,79900,90),
(4,'Deep Interior Detailing',0,99900,120),
(5,'Single Stage Polish',1,129900,180),
(6,'Multi-Stage Polish',1,249900,300),
(7,'Ceramic Coating (1 Year)',1,499900,360),
(8,'Paint Protection Film',1,null,480),
(9,'Oil Change',2,89900,45),
(10,'AC Service & Gas Refill',2,149900,90),
(11,'Brake Inspection & Service',2,119900,60),
(12,'Battery Check & Replacement',2,299900,30),
(13,'Engine Bay Steam Cleaning',3,49900,45),
(14,'Underbody Wash',3,39900,30),
(15,'Carpet & Seat Shampooing',3,79900,90),
(16,'Complete Sanitization',3,59900,60),
(17,'Bike Wash',4,null,null),
(18,'Bike Polish',4,null,null),
(19,'Chain Lube & Service',4,null,null);
commit;
