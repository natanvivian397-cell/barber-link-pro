ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS duration_min integer NOT NULL DEFAULT 30;
DROP INDEX IF EXISTS public.bookings_barber_date_time_key;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_barber_date_time_key;
CREATE UNIQUE INDEX bookings_active_slot_key ON public.bookings (barber_id, booking_date, booking_time) WHERE status <> 'cancelado';

CREATE OR REPLACE FUNCTION public.bookings_prevent_overlap()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE s int; e int;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.service_id IS NOT NULL THEN
    SELECT duration_min INTO NEW.duration_min FROM services WHERE id = NEW.service_id;
    NEW.duration_min := COALESCE(NEW.duration_min, 30);
  END IF;
  IF NEW.status = 'cancelado' OR NEW.barber_id IS NULL THEN RETURN NEW; END IF;
  s := split_part(NEW.booking_time, ':', 1)::int * 60 + split_part(NEW.booking_time, ':', 2)::int;
  e := s + NEW.duration_min;
  PERFORM pg_advisory_xact_lock(hashtext(NEW.barber_id::text || NEW.booking_date::text));
  IF EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.barber_id = NEW.barber_id AND b.booking_date = NEW.booking_date
      AND b.status <> 'cancelado' AND b.id <> NEW.id
      AND (split_part(b.booking_time, ':', 1)::int * 60 + split_part(b.booking_time, ':', 2)::int) < e
      AND (split_part(b.booking_time, ':', 1)::int * 60 + split_part(b.booking_time, ':', 2)::int) + b.duration_min > s
  ) THEN
    RAISE EXCEPTION 'Horário ocupado' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER bookings_prevent_overlap BEFORE INSERT OR UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.bookings_prevent_overlap();