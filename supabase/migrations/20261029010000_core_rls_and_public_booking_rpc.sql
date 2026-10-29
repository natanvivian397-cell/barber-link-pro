-- Core access-control hardening.
-- Public visitors can read the active catalog and availability-only data, but cannot
-- read customer records or directly write bookings. Administrative writes are checked
-- in PostgreSQL, not just by hiding UI controls.

-- Core catalog and schedule tables.
ALTER TABLE public.barbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS barbers_public_active_read ON public.barbers;
DROP POLICY IF EXISTS barbers_admin_manage ON public.barbers;
CREATE POLICY barbers_public_active_read ON public.barbers
  FOR SELECT TO anon, authenticated USING (active = true OR public.is_admin());
CREATE POLICY barbers_admin_manage ON public.barbers
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS services_public_active_read ON public.services;
DROP POLICY IF EXISTS services_admin_manage ON public.services;
CREATE POLICY services_public_active_read ON public.services
  FOR SELECT TO anon, authenticated USING (active = true OR public.is_admin());
CREATE POLICY services_admin_manage ON public.services
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS schedule_settings_public_read ON public.schedule_settings;
DROP POLICY IF EXISTS schedule_settings_admin_manage ON public.schedule_settings;
CREATE POLICY schedule_settings_public_read ON public.schedule_settings
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY schedule_settings_admin_manage ON public.schedule_settings
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Customer data is private. Only an allowlisted admin can query or mutate bookings.
DROP POLICY IF EXISTS bookings_public_read ON public.bookings;
DROP POLICY IF EXISTS bookings_admin_manage ON public.bookings;
CREATE POLICY bookings_admin_manage ON public.bookings
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

REVOKE ALL ON public.barbers, public.services, public.schedule_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.barbers, public.services, public.schedule_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.barbers, public.services, public.schedule_settings TO authenticated;
REVOKE ALL ON public.bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bookings TO authenticated;

-- Public availability endpoint: returns only the minimum fields needed to render slots.
CREATE OR REPLACE FUNCTION public.public_booking_availability(_barber_id uuid, _booking_date date)
RETURNS TABLE(booking_time text, duration_min integer, status text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT b.booking_time, b.duration_min, b.status
  FROM public.bookings b
  WHERE b.barber_id = _barber_id
    AND b.booking_date = _booking_date
    AND b.status <> 'cancelado'
$$;
REVOKE ALL ON FUNCTION public.public_booking_availability(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_booking_availability(uuid, date) TO anon, authenticated;

-- Public booking endpoint validates canonical service/barber/schedule data server-side.
CREATE OR REPLACE FUNCTION public.create_public_booking(
  _barber_id uuid,
  _service_id uuid,
  _customer_name text,
  _customer_phone text,
  _booking_date date,
  _booking_time text,
  _notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  svc public.services%ROWTYPE;
  day public.schedule_settings%ROWTYPE;
  start_min integer;
  end_min integer;
  slot_size integer;
  new_id uuid;
  phone_digits text;
BEGIN
  IF _customer_name IS NULL OR length(trim(_customer_name)) < 2 OR length(trim(_customer_name)) > 100 THEN
    RAISE EXCEPTION 'Nome inválido';
  END IF;
  phone_digits := regexp_replace(coalesce(_customer_phone, ''), '\D', '', 'g');
  IF length(phone_digits) < 10 OR length(phone_digits) > 15 THEN
    RAISE EXCEPTION 'WhatsApp inválido';
  END IF;
  IF _notes IS NOT NULL AND length(_notes) > 500 THEN
    RAISE EXCEPTION 'Observações muito longas';
  END IF;
  IF _booking_date IS NULL OR _booking_date < (now() AT TIME ZONE 'America/Sao_Paulo')::date
     OR _booking_date > (now() AT TIME ZONE 'America/Sao_Paulo')::date + 30 THEN
    RAISE EXCEPTION 'Data fora do período de agendamento';
  END IF;
  IF _booking_time IS NULL OR _booking_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION 'Horário inválido';
  END IF;

  SELECT * INTO svc FROM public.services WHERE id = _service_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Serviço indisponível'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.barbers WHERE id = _barber_id AND active = true) THEN
    RAISE EXCEPTION 'Barbeiro indisponível';
  END IF;

  SELECT * INTO day FROM public.schedule_settings
  WHERE barber_id = _barber_id
    AND weekday = extract(dow FROM _booking_date)::integer
    AND is_open = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barbearia fechada neste dia'; END IF;

  start_min := split_part(_booking_time, ':', 1)::integer * 60 + split_part(_booking_time, ':', 2)::integer;
  end_min := start_min + svc.duration_min;
  slot_size := greatest(coalesce(day.slot_min, 30), 1);

  IF NOT (
    (start_min >= split_part(day.morning_start, ':', 1)::integer * 60 + split_part(day.morning_start, ':', 2)::integer
     AND end_min <= split_part(day.morning_end, ':', 1)::integer * 60 + split_part(day.morning_end, ':', 2)::integer
     AND mod(start_min - (split_part(day.morning_start, ':', 1)::integer * 60 + split_part(day.morning_start, ':', 2)::integer), slot_size) = 0)
    OR
    (start_min >= split_part(day.afternoon_start, ':', 1)::integer * 60 + split_part(day.afternoon_start, ':', 2)::integer
     AND end_min <= split_part(day.afternoon_end, ':', 1)::integer * 60 + split_part(day.afternoon_end, ':', 2)::integer
     AND mod(start_min - (split_part(day.afternoon_start, ':', 1)::integer * 60 + split_part(day.afternoon_start, ':', 2)::integer), slot_size) = 0)
  ) THEN
    RAISE EXCEPTION 'Horário fora do expediente';
  END IF;

  IF _booking_date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
     AND _booking_time::time <= (now() AT TIME ZONE 'America/Sao_Paulo')::time THEN
    RAISE EXCEPTION 'Horário já passou';
  END IF;

  INSERT INTO public.bookings (
    barber_id, service_id, service_name, price, duration_min,
    customer_name, customer_phone, booking_date, booking_time, notes
  ) VALUES (
    _barber_id, svc.id, svc.name, svc.price, svc.duration_min,
    trim(_customer_name), trim(_customer_phone), _booking_date, _booking_time,
    nullif(trim(coalesce(_notes, '')), '')
  ) RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_public_booking(uuid, uuid, text, text, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_public_booking(uuid, uuid, text, text, date, text, text) TO anon, authenticated;
