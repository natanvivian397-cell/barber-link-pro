-- Follow-up security hardening: booking rate limits, cancellation state integrity,
-- and a hardened barber schedule initializer.
BEGIN;

-- Keep customers from changing the status of bookings that are already terminal.
-- Admins retain the existing operational ability to update any booking status.
DROP POLICY IF EXISTS bookings_update_owner_or_admin ON public.bookings;

CREATE POLICY bookings_update_owner_or_admin
ON public.bookings FOR UPDATE TO authenticated
USING (
  (
    user_id = (SELECT auth.uid())
    AND status NOT IN ('concluido', 'cancelado')
  )
  OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
)
WITH CHECK (
  (
    user_id = (SELECT auth.uid())
    AND status = 'cancelado'
  )
  OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  )
);

-- Per-authenticated-account throttle for successful booking creation.
-- The table is inaccessible to client roles; only the booking SECURITY DEFINER
-- function below can update it. This does not replace Auth/signup or edge-level
-- IP throttling, which must be configured separately in the provider.
CREATE TABLE IF NOT EXISTS public.booking_rate_limits (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  window_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT booking_rate_limits_count_nonnegative CHECK (window_count >= 0)
);

ALTER TABLE public.booking_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.booking_rate_limits FROM PUBLIC, anon, authenticated;

-- Recreate the canonical booking RPC with a transactional per-user limit.
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
  v_step integer;
  v_in_morning boolean;
  v_in_afternoon boolean;
  v_window_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Faça login para confirmar o agendamento';
  END IF;

  IF length(trim(coalesce(_customer_name, ''))) NOT BETWEEN 2 AND 100
     OR length(regexp_replace(coalesce(_customer_phone, ''), '[^0-9]', '', 'g')) NOT BETWEEN 10 AND 15
     OR length(coalesce(_notes, '')) > 500 THEN
    RAISE EXCEPTION 'Confira nome, WhatsApp e observações';
  END IF;

  IF _booking_date IS NULL
     OR _booking_date < (now() AT TIME ZONE 'America/Sao_Paulo')::date
     OR _booking_date > (now() AT TIME ZONE 'America/Sao_Paulo')::date + 30 THEN
    RAISE EXCEPTION 'Escolha uma data dentro dos próximos 30 dias';
  END IF;

  IF to_char(_booking_date, 'MM-DD') IN ('12-24','12-25','12-26','12-31','01-01','01-02') THEN
    RAISE EXCEPTION 'Barbearia fechada nesta data';
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
  v_step := greatest(5, least(coalesce(v_day.slot_min, 30), 240));

  v_in_morning :=
    v_requested_minutes >= split_part(v_day.morning_start, ':', 1)::integer * 60
                         + split_part(v_day.morning_start, ':', 2)::integer
    AND v_requested_minutes + v_service_minutes <=
        split_part(v_day.morning_end, ':', 1)::integer * 60
      + split_part(v_day.morning_end, ':', 2)::integer
    AND mod(v_requested_minutes -
      (split_part(v_day.morning_start, ':', 1)::integer * 60
       + split_part(v_day.morning_start, ':', 2)::integer), v_step) = 0;

  v_in_afternoon :=
    v_requested_minutes >= split_part(v_day.afternoon_start, ':', 1)::integer * 60
                         + split_part(v_day.afternoon_start, ':', 2)::integer
    AND v_requested_minutes + v_service_minutes <=
        split_part(v_day.afternoon_end, ':', 1)::integer * 60
      + split_part(v_day.afternoon_end, ':', 2)::integer
    AND mod(v_requested_minutes -
      (split_part(v_day.afternoon_start, ':', 1)::integer * 60
       + split_part(v_day.afternoon_start, ':', 2)::integer), v_step) = 0;

  IF NOT (v_in_morning OR v_in_afternoon) THEN
    RAISE EXCEPTION 'Horário fora do expediente ou da grade disponível';
  END IF;

  -- Atomically allow at most five successful booking attempts per account
  -- in each rolling ten-minute window.
  INSERT INTO public.booking_rate_limits AS limits (
    user_id, window_started_at, window_count, updated_at
  )
  VALUES (v_user_id, now(), 1, now())
  ON CONFLICT (user_id) DO UPDATE
  SET
    window_started_at = CASE
      WHEN limits.window_started_at <= now() - interval '10 minutes' THEN now()
      ELSE limits.window_started_at
    END,
    window_count = CASE
      WHEN limits.window_started_at <= now() - interval '10 minutes' THEN 1
      ELSE limits.window_count + 1
    END,
    updated_at = now()
  RETURNING window_count INTO v_window_count;

  IF v_window_count > 5 THEN
    RAISE EXCEPTION 'Muitos agendamentos em pouco tempo. Aguarde alguns minutos.';
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

-- The schedule initializer is a trigger-only SECURITY DEFINER function.
-- Empty search_path and schema-qualified relations prevent object shadowing.
CREATE OR REPLACE FUNCTION public.initialize_barber_schedule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  source_barber_id uuid;
BEGIN
  SELECT b.id INTO source_barber_id
  FROM public.barbers AS b
  WHERE b.id <> NEW.id
  ORDER BY b.sort_order, b.created_at
  LIMIT 1;

  IF source_barber_id IS NOT NULL THEN
    INSERT INTO public.schedule_settings (
      barber_id, weekday, is_open, morning_start, morning_end,
      afternoon_start, afternoon_end, slot_min
    )
    SELECT
      NEW.id, s.weekday, s.is_open, s.morning_start, s.morning_end,
      s.afternoon_start, s.afternoon_end, s.slot_min
    FROM public.schedule_settings AS s
    WHERE s.barber_id = source_barber_id
    ON CONFLICT (barber_id, weekday) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.initialize_barber_schedule() FROM PUBLIC, anon, authenticated;

COMMIT;
