-- Defense-in-depth RLS and booking data minimization.
-- Keeps public booking creation and availability while preventing public reads of customer PII.
-- Admin writes are limited to the two explicitly authorized accounts.

BEGIN;

-- Public catalog reads; administrative writes only for the allowlisted accounts.
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('services', 'barbers', 'schedule_settings', 'schedule_blocks', 'bookings')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY services_public_read ON public.services
  FOR SELECT TO anon, authenticated USING (active = true);
CREATE POLICY services_admin_manage ON public.services
  FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

CREATE POLICY barbers_public_read ON public.barbers
  FOR SELECT TO anon, authenticated USING (active = true);
CREATE POLICY barbers_admin_manage ON public.barbers
  FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

CREATE POLICY schedule_settings_public_read ON public.schedule_settings
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY schedule_settings_admin_manage ON public.schedule_settings
  FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

CREATE POLICY blocks_public_read ON public.schedule_blocks
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY blocks_admin_manage ON public.schedule_blocks
  FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

-- The holiday trigger must still be able to read the closure calendar under RLS.
DO $$
BEGIN
  IF to_regclass('public.booking_blocked_dates') IS NOT NULL THEN
    ALTER TABLE public.booking_blocked_dates ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS blocked_dates_public_read ON public.booking_blocked_dates;
    CREATE POLICY blocked_dates_public_read ON public.booking_blocked_dates
      FOR SELECT TO anon, authenticated USING (true);
    GRANT SELECT ON public.booking_blocked_dates TO anon, authenticated;
  END IF;
END $$;

-- Customers may create a booking, but may not read the underlying bookings table.
-- Only allowlisted admins can read or change existing booking rows.
CREATE POLICY bookings_public_insert ON public.bookings
  FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY bookings_admin_manage ON public.bookings
  FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

-- Public access to bookings is limited to a safe availability view, not names/phones/notes/prices.
CREATE OR REPLACE VIEW public.booking_slots WITH (security_barrier = true) AS
  SELECT barber_id, booking_date, booking_time, duration_min, status
  FROM public.bookings;

GRANT SELECT ON public.services, public.barbers, public.schedule_settings, public.schedule_blocks TO anon, authenticated;
GRANT SELECT, UPDATE, DELETE ON public.bookings TO authenticated;
REVOKE ALL ON public.bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE, DELETE ON public.bookings TO authenticated;
GRANT INSERT (barber_id, customer_name, customer_phone, service_id, service_name, price, booking_date, booking_time, notes)
  ON public.bookings TO anon, authenticated;
-- The recurring-client RPC is SECURITY INVOKER and inserts duration_min too.
GRANT INSERT (duration_min) ON public.bookings TO authenticated;
GRANT SELECT ON public.booking_slots TO anon, authenticated;

-- A safe realtime signal replaces public subscriptions to the customer-data table.
CREATE TABLE IF NOT EXISTS public.booking_slot_events (
  id smallint PRIMARY KEY CHECK (id = 1),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.booking_slot_events (id, changed_at)
VALUES (1, clock_timestamp())
ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.booking_slot_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS booking_slot_events_public_read ON public.booking_slot_events;
CREATE POLICY booking_slot_events_public_read ON public.booking_slot_events
  FOR SELECT TO anon, authenticated USING (true);
GRANT SELECT ON public.booking_slot_events TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.booking_slot_events FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.signal_booking_slot_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.booking_slot_events (id, changed_at)
  VALUES (1, clock_timestamp())
  ON CONFLICT (id) DO UPDATE SET changed_at = EXCLUDED.changed_at;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_signal_slot_change ON public.bookings;
CREATE TRIGGER bookings_signal_slot_change
AFTER INSERT OR UPDATE OR DELETE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.signal_booking_slot_change();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'booking_slot_events'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_slot_events;
  END IF;
END $$;

-- Ensure customer cancellation functions are callable only through the intended API roles.
REVOKE ALL ON FUNCTION public.find_my_bookings(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_my_bookings(text, text) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_my_booking(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_my_booking(uuid, text, text) TO anon, authenticated;

-- Restrictive guards protect the catalog bucket even if another permissive Storage policy exists.
DROP POLICY IF EXISTS catalog_photos_upload_allowlist_guard ON storage.objects;
CREATE POLICY catalog_photos_upload_allowlist_guard ON storage.objects
  AS RESTRICTIVE FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));
DROP POLICY IF EXISTS catalog_photos_update_allowlist_guard ON storage.objects;
CREATE POLICY catalog_photos_update_allowlist_guard ON storage.objects
  AS RESTRICTIVE FOR UPDATE TO anon, authenticated
  USING (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));
DROP POLICY IF EXISTS catalog_photos_delete_allowlist_guard ON storage.objects;
CREATE POLICY catalog_photos_delete_allowlist_guard ON storage.objects
  AS RESTRICTIVE FOR DELETE TO anon, authenticated
  USING (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

-- Keep the existing recurring-client function implementation unchanged to avoid
-- altering schedule, conflict, or blocked-slot behavior. It is SECURITY INVOKER,
-- and the RLS policies above restrict its writes to the two allowlisted admins.
REVOKE ALL ON FUNCTION public.book_fixed_client(uuid, uuid, text, text, integer, text, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_fixed_client(uuid, uuid, text, text, integer, text, date, date) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
