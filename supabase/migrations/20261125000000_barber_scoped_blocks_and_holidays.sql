-- 1) Per-barber schedule blocks: every existing query and trigger already
--    scopes by barber_id, so a block for one barber never hides another
--    barber's slot. The unique constraint remains per barber/date/time.

-- 2) Recurring year-end / new-year closure: a single static lookup table keeps
--    every future year blocked (2026–2036 included) without creating duplicates.
CREATE TABLE IF NOT EXISTS public.booking_blocked_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocked_date date NOT NULL UNIQUE
);

INSERT INTO public.booking_blocked_dates (blocked_date) VALUES
  ('2026-12-24'), ('2026-12-25'), ('2026-12-26'), ('2026-12-31'),
  ('2027-01-01'), ('2027-01-02'),
  ('2027-12-24'), ('2027-12-25'), ('2027-12-26'), ('2027-12-31'),
  ('2028-01-01'), ('2028-01-02'),
  ('2028-12-24'), ('2028-12-25'), ('2028-12-26'), ('2028-12-31'),
  ('2029-01-01'), ('2029-01-02'),
  ('2029-12-24'), ('2029-12-25'), ('2029-12-26'), ('2029-12-31'),
  ('2030-01-01'), ('2030-01-02'),
  ('2030-12-24'), ('2030-12-25'), ('2030-12-26'), ('2030-12-31'),
  ('2031-01-01'), ('2031-01-02'),
  ('2031-12-24'), ('2031-12-25'), ('2031-12-26'), ('2031-12-31'),
  ('2032-01-01'), ('2032-01-02'),
  ('2032-12-24'), ('2032-12-25'), ('2032-12-26'), ('2032-12-31'),
  ('2033-01-01'), ('2033-01-02'),
  ('2033-12-24'), ('2033-12-25'), ('2033-12-26'), ('2033-12-31'),
  ('2034-01-01'), ('2034-01-02'),
  ('2034-12-24'), ('2034-12-25'), ('2034-12-26'), ('2034-12-31'),
  ('2035-01-01'), ('2035-01-02'),
  ('2035-12-24'), ('2035-12-25'), ('2035-12-26'), ('2035-12-31'),
  ('2036-01-01'), ('2036-01-02')
ON CONFLICT (blocked_date) DO NOTHING;

GRANT SELECT ON public.booking_blocked_dates TO anon, authenticated;
ALTER TABLE public.booking_blocked_dates ENABLE ROW LEVEL SECURITY;
CREATE POLICY blocked_dates_public_read ON public.booking_blocked_dates
  FOR SELECT TO anon, authenticated USING (true);

-- 3) Enforce the blocked dates at booking time (no new bookings on those days).
CREATE OR REPLACE FUNCTION public.prevent_booking_on_blocked_date()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.booking_date IN (SELECT blocked_date FROM public.booking_blocked_dates) THEN
    RAISE EXCEPTION 'Barbearia fechada nesta data' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER bookings_reject_blocked_dates
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.prevent_booking_on_blocked_date();
