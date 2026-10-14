begin;
insert into auth.users(id,email) values('00000000-0000-4000-a000-000000000001','profile-test-1@example.invalid'),('00000000-0000-4000-a000-000000000002','profile-test-2@example.invalid');
insert into public.carmitra_profiles(user_id,full_name,phone)values('00000000-0000-4000-a000-000000000001','Fixture','9000000001')on conflict(user_id)do nothing;
insert into public.carmitra_reward_points(user_id,points,description)values('00000000-0000-4000-a000-000000000001',10,'Rollback-only reward'),('00000000-0000-4000-a000-000000000002',99,'Another account');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-a000-000000000001',true);
do $$declare blocked boolean;begin
insert into storage.objects(bucket_id,name,owner_id)values('carmitra-avatars','00000000-0000-4000-a000-000000000001/profile/photo.jpg','00000000-0000-4000-a000-000000000001');
update public.carmitra_profiles set gender='female',contact_email='contact@example.invalid',photo_path='00000000-0000-4000-a000-000000000001/profile/photo.jpg',date_of_birth='2000-02-29'where user_id=auth.uid();
if not exists(select 1 from public.carmitra_profiles where user_id=auth.uid()and gender='female'and contact_email='contact@example.invalid'and photo_path is not null)then raise exception 'Profile save failed';end if;
blocked:=false;begin insert into storage.objects(bucket_id,name,owner_id)values('carmitra-avatars','00000000-0000-4000-a000-000000000002/profile/photo.jpg','00000000-0000-4000-a000-000000000001');exception when others then blocked:=true;end;if not blocked then raise exception 'Cross-user avatar upload allowed';end if;
if (public.carmitra_my_points()->>'balance')::integer<>10 then raise exception 'Wrong reward balance or privacy leak';end if;
blocked:=false;begin insert into public.carmitra_reward_points(user_id,points,description)values(auth.uid(),10000,'User inflation');exception when others then blocked:=true;end;if not blocked then raise exception 'User can mint points';end if;
end $$;
rollback;
select 'PASS: photo/gender/email/DOB persistence, avatar ownership policies, actual reward balance and blocked points inflation; fixtures rolled back' result;
