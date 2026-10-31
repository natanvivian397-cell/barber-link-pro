-- Customer accounts: every new public booking is tied to the authenticated Supabase user.
-- Historical rows keep user_id NULL and remain visible only to the authorized barbershop admins.
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS bookings_user_id_date_idx
  ON public.bookings (user_id, booking_date, booking_time);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

-- Replace every pre-existing bookings policy so permissive legacy policies cannot
-- accidentally OR-bypass the owner/admin boundary.
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'bookings'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.bookings', p.policyname);
  END LOOP;
END $$;

REVOKE ALL ON TABLE public.bookings FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.bookings TO authenticated;
REVOKE UPDATE ON TABLE public.bookings FROM authenticated;
GRANT UPDATE (status) ON TABLE public.bookings TO authenticated;

CREATE POLICY bookings_select_owner_or_admin
ON public.bookings FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
);

CREATE POLICY bookings_insert_admin_only
ON public.bookings FOR INSERT TO authenticated
WITH CHECK (
  lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
);

CREATE POLICY bookings_update_owner_or_admin
ON public.bookings FOR UPDATE TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
)
WITH CHECK (
  (user_id = (SELECT auth.uid()) AND status = 'cancelado')
  OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
);

CREATE POLICY bookings_delete_admin_only
ON public.bookings FOR DELETE TO authenticated
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
);

-- Public availability exposes only the time and duration of occupied slots.
-- It never returns customer names, phone numbers, notes, prices or booking IDs.
CREATE OR REPLACE FUNCTION public.get_public_booking_slots(
  _barber_id uuid,
  _booking_date date
)
RETURNS TABLE (booking_time text, duration_min integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT b.booking_time::text, b.duration_min
  FROM public.bookings AS b
  WHERE b.barber_id = _barber_id
    AND b.booking_date = _booking_date
    AND b.status <> 'cancelado'
$$;

REVOKE ALL ON FUNCTION public.get_public_booking_slots(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_booking_slots(uuid, date) TO anon, authenticated;

-- Create bookings only from a real authenticated session. The user_id comes
-- exclusively from auth.uid(); no client-supplied user ID is accepted.
CREATE OR REPLACE FUNCTION public.create_booking_authenticated(
  _barber_id uuid,
  _customer_name text,
  _customer_phone text,
  _service_id uuid,
  _booking_date date,
  _booking_time text,
  _notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_booking_id uuid;
  v_service public.services%ROWTYPE;
  v_day public.schedule_settings%ROWTYPE;
  v_requested_minutes integer;
  v_service_minutes integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Faça login para confirmar o agendamento';
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

  SELECT * INTO v_service
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

  SELECT * INTO v_day
  FROM public.schedule_settings
  WHERE barber_id = _barber_id
    AND weekday = extract(dow FROM _booking_date)::integer
    AND is_open;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dia fechado';
  END IF;

  v_requested_minutes := split_part(_booking_time, ':', 1)::integer * 60
                       + split_part(_booking_time, ':', 2)::integer;
  v_service_minutes := coalesce(v_service.duration_min, 30);

  IF NOT (
    (
      v_requested_minutes >= split_part(v_day.morning_start, ':', 1)::integer * 60
                          + split_part(v_day.morning_start, ':', 2)::integer
      AND v_requested_minutes + v_service_minutes <=
          split_part(v_day.morning_end, ':', 1)::integer * 60
        + split_part(v_day.morning_end, ':', 2)::integer
    )
    OR
    (
      v_requested_minutes >= split_part(v_day.afternoon_start, ':', 1)::integer * 60
                          + split_part(v_day.afternoon_start, ':', 2)::integer
      AND v_requested_minutes + v_service_minutes <=
          split_part(v_day.afternoon_end, ':', 1)::integer * 60
        + split_part(v_day.afternoon_end, ':', 2)::integer
    )
  ) THEN
    RAISE EXCEPTION 'Serviço fora do expediente';
  END IF;

  INSERT INTO public.bookings (
    user_id, barber_id, customer_name, customer_phone, service_id,
    service_name, price, duration_min, booking_date, booking_time, notes
  )
  VALUES (
    v_user_id, _barber_id, trim(_customer_name),
    trim(_customer_phone), v_service.id, v_service.name,
    v_service.price, v_service_minutes, _booking_date, _booking_time,
    nullif(trim(coalesce(_notes, '')), '')
  )
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_booking_authenticated(uuid, text, text, uuid, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_booking_authenticated(uuid, text, text, uuid, date, text, text) TO authenticated;

-- Disable the previous device-token and name/phone based customer endpoints.
-- Historical bookings are not claimed by a customer; only admins can see them.
REVOKE ALL ON FUNCTION public.create_booking_for_device(uuid, text, text, uuid, text, numeric, date, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.find_my_bookings_by_device(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_my_bookings_for_device(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_my_booking_by_device(uuid, text) FROM PUBLIC, anon, authenticated;
DO $
BEGIN
  IF to_regprocedure('public.find_my_bookings(text,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.find_my_bookings(text, text) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.cancel_my_booking(uuid,text,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.cancel_my_booking(uuid, text, text) FROM PUBLIC, anon, authenticated';
  END IF;
END $;
