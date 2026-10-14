create function carmitra_internal.slot_integrity() returns trigger language plpgsql security definer set search_path='' as $$declare reserved integer;begin
 select count(*) into reserved from public.carmitra_bookings where slot_id=old.id and status<>'cancelled' and (status<>'awaiting_payment' or expires_at>now());
 if reserved>0 and (new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at) then raise exception 'This slot has bookings. Create a new time window instead';end if;
 if new.capacity<reserved then raise exception 'Capacity cannot be lower than existing reservations';end if;return new;end$$;
revoke all on function carmitra_internal.slot_integrity() from public,anon,authenticated;
create trigger carmitra_slot_integrity before update on public.carmitra_slots for each row execute function carmitra_internal.slot_integrity();
