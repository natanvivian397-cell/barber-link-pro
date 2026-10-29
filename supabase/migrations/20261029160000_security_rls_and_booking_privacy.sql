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
      AND tablename IN ('services', 'barbers', 'schedule_settings', 'schedule_blocks', 'bookings', 'booking_blocked_dates')
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
REVOKE ALL ON public.bookings FROM anon, authenticated;
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
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));
DROP POLICY IF EXISTS catalog_photos_update_allowlist_guard ON storage.objects;
CREATE POLICY catalog_photos_update_allowlist_guard ON storage.objects
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'))
  WITH CHECK (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));
DROP POLICY IF EXISTS catalog_photos_delete_allowlist_guard ON storage.objects;
CREATE POLICY catalog_photos_delete_allowlist_guard ON storage.objects
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING (bucket_id <> 'catalog-photos' OR lower(coalesce(auth.jwt() ->> 'email', '')) IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com'));

-- Validate authoritative booking data server-side instead of trusting client-submitted prices/durations.
CREATE OR REPLACE FUNCTION public.validate_booking_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  svc public.services%ROWTYPE;
  day public.schedule_settings%ROWTYPE;
  start_minutes integer;
  end_minutes integer;
  requested_minutes integer;
  local_today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  local_time time := (now() AT TIME ZONE 'America/Sao_Paulo')::time;
BEGIN
  IF NEW.barber_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.barbers WHERE id = NEW.barber_id AND active = true
  ) THEN
    RAISE EXCEPTION 'Barbeiro indisponível';
  END IF;

  SELECT * INTO svc FROM public.services WHERE id = NEW.service_id AND active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Serviço indisponível';
  END IF;

  IF NEW.booking_date IS NULL OR NEW.booking_time IS NULL OR NEW.booking_date < local_today OR NEW.booking_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION 'Data ou horário inválido';
  END IF;

  SELECT * INTO day FROM public.schedule_settings
  WHERE barber_id = NEW.barber_id
    AND weekday = extract(dow FROM NEW.booking_date)::integer
    AND is_open = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Barbeiro fechado nesta data';
  END IF;

  requested_minutes := split_part(NEW.booking_time, ':', 1)::integer * 60
                     + split_part(NEW.booking_time, ':', 2)::integer;
  start_minutes := split_part(day.morning_start, ':', 1)::integer * 60
                 + split_part(day.morning_start, ':', 2)::integer;
  end_minutes := split_part(day.morning_end, ':', 1)::integer * 60
               + split_part(day.morning_end, ':', 2)::integer;

  IF NOT (
    (requested_minutes >= start_minutes
      AND requested_minutes + svc.duration_min <= end_minutes
      AND mod(requested_minutes - start_minutes, greatest(day.slot_min, 1)) = 0)
    OR
    (requested_minutes >= split_part(day.afternoon_start, ':', 1)::integer * 60
                          + split_part(day.afternoon_start, ':', 2)::integer
      AND requested_minutes + svc.duration_min <= split_part(day.afternoon_end, ':', 1)::integer * 60
                                                   + split_part(day.afternoon_end, ':', 2)::integer
      AND mod(requested_minutes - (split_part(day.afternoon_start, ':', 1)::integer * 60
                                   + split_part(day.afternoon_start, ':', 2)::integer),
              greatest(day.slot_min, 1)) = 0)
  ) THEN
    RAISE EXCEPTION 'Horário fora do expediente';
  END IF;

  IF NEW.booking_date = local_today AND NEW.booking_time::time <= local_time THEN
    RAISE EXCEPTION 'Horário já passou';
  END IF;

  -- Service name, price and duration are read from the database, never trusted from the browser.
  NEW.service_name := svc.name;
  NEW.price := svc.price;
  NEW.duration_min := svc.duration_min;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_validate_insert ON public.bookings;
CREATE TRIGGER bookings_validate_insert
BEFORE INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.validate_booking_insert();

-- Lock down the recurring booking RPC to the same allowlisted admin accounts.
CREATE OR REPLACE FUNCTION public.book_fixed_client(_barber uuid, _service uuid, _name text, _phone text, _weekday integer, _time text, _start date, _end date)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE svc public.services%ROWTYPE; day public.schedule_settings%ROWTYPE; d date; n integer := 0; minutes integer;
BEGIN
 IF lower(coalesce(auth.jwt() ->> 'email', '')) NOT IN ('natanvivian39@gmail.com', 'douglasmachadodigao@gmail.com') THEN
   RAISE EXCEPTION 'Acesso não autorizado';
 END IF;
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no painel'; END IF;
 IF length(trim(_name)) < 2 OR length(regexp_replace(_phone, '\D', '', 'g')) < 10 THEN RAISE EXCEPTION 'Informe nome e WhatsApp'; END IF;
 IF _weekday NOT BETWEEN 0 AND 6 OR _start IS NULL OR _end IS NULL OR _start < (now() AT TIME ZONE 'America/Sao_Paulo')::date OR _end < _start OR _end > _start + 366 THEN RAISE EXCEPTION 'Escolha um período futuro de até um ano'; END IF;
 IF _time IS NULL OR _time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Horário inválido'; END IF;
 SELECT * INTO svc FROM public.services WHERE id = _service AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escolha um serviço ativo'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.barbers WHERE id = _barber AND active) THEN RAISE EXCEPTION 'Escolha um barbeiro ativo'; END IF;
 SELECT * INTO day FROM public.schedule_settings WHERE barber_id = _barber AND weekday = _weekday AND is_open;
 IF NOT FOUND THEN RAISE EXCEPTION 'Dia fechado'; END IF;
 minutes := split_part(_time, ':', 1)::integer * 60 + split_part(_time, ':', 2)::integer;
 IF NOT ((minutes >= split_part(day.morning_start, ':', 1)::integer * 60 + split_part(day.morning_start, ':', 2)::integer AND minutes + svc.duration_min <= split_part(day.morning_end, ':', 1)::integer * 60 + split_part(day.morning_end, ':', 2)::integer) OR (minutes >= split_part(day.afternoon_start, ':', 1)::integer * 60 + split_part(day.afternoon_start, ':', 2)::integer AND minutes + svc.duration_min <= split_part(day.afternoon_end, ':', 1)::integer * 60 + split_part(day.afternoon_end, ':', 2)::integer)) THEN RAISE EXCEPTION 'Serviço fora do expediente'; END IF;
 FOR d IN SELECT x::date FROM generate_series(_start::timestamp, _end::timestamp, interval '1 day') x WHERE extract(dow FROM x) = _weekday LOOP
  IF d = (now() AT TIME ZONE 'America/Sao_Paulo')::date AND _time::time <= (now() AT TIME ZONE 'America/Sao_Paulo')::time THEN RAISE EXCEPTION 'Horário já passou'; END IF;
  INSERT INTO public.bookings(barber_id, service_id, service_name, price, duration_min, customer_name, customer_phone, booking_date, booking_time, notes) VALUES (_barber, svc.id, svc.name, svc.price, svc.duration_min, trim(_name), _phone, d, _time, 'Cliente fixo · semanal');
  n := n + 1;
 END LOOP;
 IF n = 0 THEN RAISE EXCEPTION 'Nenhuma ocorrência neste período'; END IF;
 RETURN n;
END; $$;
REVOKE ALL ON FUNCTION public.book_fixed_client(uuid, uuid, text, text, integer, text, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_fixed_client(uuid, uuid, text, text, integer, text, date, date) TO authenticated;

COMMIT;
