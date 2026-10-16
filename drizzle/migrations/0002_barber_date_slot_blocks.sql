CREATE TABLE public.schedule_blocks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 barber_id uuid NOT NULL REFERENCES public.barbers(id) ON DELETE CASCADE,
 booking_date date NOT NULL,
 booking_time text NOT NULL CHECK (booking_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
 duration_min integer NOT NULL DEFAULT 30 CHECK (duration_min > 0 AND duration_min <= 1440),
 UNIQUE (barber_id, booking_date, booking_time)
);
GRANT SELECT ON public.schedule_blocks TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.schedule_blocks TO authenticated;
GRANT ALL ON public.schedule_blocks TO service_role;
ALTER TABLE public.schedule_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY blocks_public_read ON public.schedule_blocks FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY blocks_staff_manage ON public.schedule_blocks FOR ALL TO authenticated USING (true) WITH CHECK (true);
ALTER PUBLICATION supabase_realtime ADD TABLE public.schedule_blocks;
CREATE FUNCTION public.prevent_booking_in_block() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE s integer;
BEGIN
 IF NEW.status = 'cancelado' OR NEW.barber_id IS NULL THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(NEW.barber_id::text || NEW.booking_date::text));
 s := split_part(NEW.booking_time, ':', 1)::integer * 60 + split_part(NEW.booking_time, ':', 2)::integer;
 IF EXISTS (SELECT 1 FROM public.schedule_blocks b WHERE b.barber_id = NEW.barber_id AND b.booking_date = NEW.booking_date AND split_part(b.booking_time, ':', 1)::integer * 60 + split_part(b.booking_time, ':', 2)::integer < s + NEW.duration_min AND split_part(b.booking_time, ':', 1)::integer * 60 + split_part(b.booking_time, ':', 2)::integer + b.duration_min > s) THEN
 RAISE EXCEPTION 'Horário bloqueado' USING ERRCODE = '23505';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER bookings_reject_block BEFORE INSERT OR UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.prevent_booking_in_block();
CREATE FUNCTION public.prevent_block_on_booking() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE s integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext(NEW.barber_id::text || NEW.booking_date::text));
 s := split_part(NEW.booking_time, ':', 1)::integer * 60 + split_part(NEW.booking_time, ':', 2)::integer;
 IF EXISTS (SELECT 1 FROM public.bookings b WHERE b.barber_id = NEW.barber_id AND b.booking_date = NEW.booking_date AND b.status <> 'cancelado' AND split_part(b.booking_time, ':', 1)::integer * 60 + split_part(b.booking_time, ':', 2)::integer < s + NEW.duration_min AND split_part(b.booking_time, ':', 1)::integer * 60 + split_part(b.booking_time, ':', 2)::integer + b.duration_min > s) THEN
 RAISE EXCEPTION 'Horário já agendado' USING ERRCODE = '23505';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER blocks_reject_bookings BEFORE INSERT OR UPDATE ON public.schedule_blocks FOR EACH ROW EXECUTE FUNCTION public.prevent_block_on_booking();