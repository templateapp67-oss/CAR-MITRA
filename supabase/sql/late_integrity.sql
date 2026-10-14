-- Already applied to CAR-MITRA. Reference for reconstructing the schema after initial SQL scripts.
begin;
alter table public.carmitra_user_subscriptions add column paid_price_paise integer check(paid_price_paise>0),add column included_washes integer check(included_washes>0);
alter table public.carmitra_subscription_plans add constraint carmitra_plan_limits check(valid_days between 1 and 365 and washes between 1 and 1000 and price_paise>=washes);
alter table public.carmitra_coupons add constraint carmitra_coupon_minimum check(minimum_paise>=0);
alter table public.carmitra_site_settings add column emergency_number text not null default '112' check(emergency_number='' or emergency_number~'^[0-9]{3,15}$');
commit;
-- Latest function definitions (including money, OTP and role fixes) are in live_routines_snapshot.sql.
