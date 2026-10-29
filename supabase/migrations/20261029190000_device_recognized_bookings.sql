-- Device-based appointment lookup.
-- The device token is stored only in this private mapping table, never on bookings.
CREATE TABLE IF NOT EXISTS public.booking_device_access (
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  device_token text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (booking_id, device_token)
);

CREATE INDEX IF NOT EXISTS booking_device_access_token_idx
  ON public.booking_device_access (device_token);

ALTER TABLE public.booking_device_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.booking_device_access FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_booking_for_device(
  _barber_id uuid,
  _customer_name text,
  _customer_phone text,
  _service_id uuid,
  _service_name text,
  _price numeric,
  _booking_date date,
  _booking_time text,
  _notes text,
  _device_token text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_booking_id uuid;
  svc public.services%ROWTYPE;
  day_settings public.schedule_settings%ROWTYPE;
  requested_minutes integer;
  service_minutes integer;
BEGIN
  -- The browser token is only a convenience identifier, never user-supplied booking authority.
  IF length(coalesce(_device_token, '')) < 50 OR length(_device_token) > 200 THEN
    RAISE EXCEPTION 'Identificação do dispositivo inválida';
  END IF;
  IF length(trim(coalesce(_customer_name, ''))) < 2
     OR length(regexp_replace(coalesce(_customer_phone, ''), '[^0-9]', '', 'g')) < 10 THEN
    RAISE EXCEPTION 'Informe nome e WhatsApp válidos';
  END IF;
  IF _booking_date IS NULL
     OR _booking_date < (now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
    RAISE EXCEPTION 'Escolha uma data válida';
  END IF;
  IF _booking_time IS NULL OR _booking_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION 'Horário inválido';
  END IF;
  IF _booking_date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
     AND _booking_time::time <= (now() AT TIME ZONE 'America/Sao_Paulo')::time THEN
    RAISE EXCEPTION 'Horário já passou';
  END IF;

  SELECT * INTO svc
  FROM public.services
  WHERE id = _service_id AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Escolha um serviço ativo';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.barbers WHERE id = _barber_id AND active
  ) THEN
    RAISE EXCEPTION 'Escolha um barbeiro ativo';
  END IF;

  SELECT * INTO day_settings
  FROM public.schedule_settings
  WHERE barber_id = _barber_id
    AND weekday = extract(dow FROM _booking_date)::integer
    AND is_open;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dia fechado';
  END IF;

  requested_minutes := split_part(_booking_time, ':', 1)::integer * 60
                     + split_part(_booking_time, ':', 2)::integer;
  service_minutes := coalesce(svc.duration_min, 30);

  IF NOT (
    (
      requested_minutes >= split_part(day_settings.morning_start, ':', 1)::integer * 60
                        + split_part(day_settings.morning_start, ':', 2)::integer
      AND requested_minutes + service_minutes <=
          split_part(day_settings.morning_end, ':', 1)::integer * 60
        + split_part(day_settings.morning_end, ':', 2)::integer
    )
    OR
    (
      requested_minutes >= split_part(day_settings.afternoon_start, ':', 1)::integer * 60
                        + split_part(day_settings.afternoon_start, ':', 2)::integer
      AND requested_minutes + service_minutes <=
          split_part(day_settings.afternoon_end, ':', 1)::integer * 60
        + split_part(day_settings.afternoon_end, ':', 2)::integer
    )
  ) THEN
    RAISE EXCEPTION 'Serviço fora do expediente';
  END IF;

  -- Use canonical service details from the database rather than trusting client-sent price/name.
  -- Existing database triggers remain responsible for overlaps, blocked slots and blocked dates.
  INSERT INTO public.bookings (
    barber_id, customer_name, customer_phone, service_id, service_name,
    price, duration_min, booking_date, booking_time, notes
  )
  VALUES (
    _barber_id, trim(_customer_name), trim(_customer_phone), svc.id, svc.name,
    svc.price, service_minutes, _booking_date, _booking_time,
    nullif(trim(coalesce(_notes, '')), '')
  )
  RETURNING id INTO new_booking_id;

  INSERT INTO public.booking_device_access (booking_id, device_token)
  VALUES (new_booking_id, _device_token);

  RETURN new_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.find_my_bookings_by_device(_device_token text)
RETURNS TABLE(id uuid, service_name text, booking_date date, booking_time text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.id, b.service_name, b.booking_date, b.booking_time
  FROM public.bookings b
  JOIN public.booking_device_access d ON d.booking_id = b.id
  WHERE d.device_token = _device_token
    AND length(coalesce(_device_token, '')) >= 50
    AND b.status NOT IN ('cancelado', 'concluido')
    AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
  ORDER BY b.booking_date, b.booking_time
$$;

-- One-time migration path for bookings made before device recognition existed.
-- It links only bookings matching the name + phone the customer already used.
CREATE OR REPLACE FUNCTION public.claim_my_bookings_for_device(
  _name text,
  _phone text,
  _device_token text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  linked_count integer;
BEGIN
  IF length(coalesce(_device_token, '')) < 50 OR length(_device_token) > 200
     OR length(regexp_replace(coalesce(_phone, ''), '[^0-9]', '', 'g')) < 10
     OR length(trim(coalesce(_name, ''))) < 2 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.booking_device_access (booking_id, device_token)
  SELECT b.id, _device_token
  FROM public.bookings b
  WHERE (lower(trim(b.customer_name)) = lower(trim(_name))
         OR split_part(lower(trim(b.customer_name)), ' ', 1) = split_part(lower(trim(_name)), ' ', 1))
    AND regexp_replace(b.customer_phone, '[^0-9]', '', 'g') =
        regexp_replace(_phone, '[^0-9]', '', 'g')
    AND b.status NOT IN ('cancelado', 'concluido')
    AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
  ON CONFLICT (booking_id, device_token) DO NOTHING;

  GET DIAGNOSTICS linked_count = ROW_COUNT;
  RETURN linked_count;
END;
$$;

REVOKE ALL ON FUNCTION public.create_booking_for_device(uuid, text, text, uuid, text, numeric, date, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_my_bookings_by_device(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_my_bookings_for_device(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_booking_for_device(uuid, text, text, uuid, text, numeric, date, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_my_bookings_by_device(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_my_bookings_for_device(text, text, text) TO anon, authenticated;


-- Allow a booking to be cancelled only from the browser token already linked to it.
CREATE OR REPLACE FUNCTION public.cancel_my_booking_by_device(
  _booking_id uuid,
  _device_token text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cancelled_id uuid;
BEGIN
  IF length(coalesce(_device_token, '')) < 50 OR length(_device_token) > 200 THEN
    RETURN false;
  END IF;

  UPDATE public.bookings b
  SET status = 'cancelado'
  WHERE b.id = _booking_id
    AND EXISTS (
      SELECT 1
      FROM public.booking_device_access d
      WHERE d.booking_id = b.id
        AND d.device_token = _device_token
    )
    AND b.status NOT IN ('cancelado', 'concluido')
    AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
  RETURNING b.id INTO cancelled_id;

  RETURN cancelled_id IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_my_booking_by_device(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_my_booking_by_device(uuid, text) TO anon, authenticated;
