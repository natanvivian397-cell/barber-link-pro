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
BEGIN
  IF length(coalesce(_device_token, '')) < 50 OR length(_device_token) > 200 THEN
    RAISE EXCEPTION 'Identificação do dispositivo inválida';
  END IF;

  INSERT INTO public.bookings (
    barber_id, customer_name, customer_phone, service_id, service_name,
    price, booking_date, booking_time, notes
  )
  VALUES (
    _barber_id, trim(_customer_name), trim(_customer_phone), _service_id, _service_name,
    _price, _booking_date, _booking_time, nullif(trim(coalesce(_notes, '')), '')
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
     OR length(regexp_replace(coalesce(_phone, ''), '\\D', '', 'g')) < 10
     OR length(trim(coalesce(_name, ''))) < 2 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.booking_device_access (booking_id, device_token)
  SELECT b.id, _device_token
  FROM public.bookings b
  WHERE lower(trim(b.customer_name)) = lower(trim(_name))
    AND regexp_replace(b.customer_phone, '\\D', '', 'g') =
        regexp_replace(_phone, '\\D', '', 'g')
    AND b.status NOT IN ('cancelado', 'concluido')
    AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
  ON CONFLICT (booking_id, device_token) DO NOTHING;

  GET DIAGNOSTICS linked_count = ROW_COUNT;
  RETURN linked_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_booking_for_device(uuid, text, text, uuid, text, numeric, date, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_my_bookings_by_device(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_my_bookings_for_device(text, text, text) TO anon, authenticated;
