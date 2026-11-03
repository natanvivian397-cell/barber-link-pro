DROP TRIGGER IF EXISTS bookings_require_user_id ON public.bookings;

CREATE OR REPLACE FUNCTION public.create_booking_authenticated(_barber_id uuid, _customer_name text, _customer_phone text, _service_id uuid, _booking_date date, _booking_time text, _notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_phone_digits text := regexp_replace(coalesce(_customer_phone, ''), '[^0-9]', '', 'g');
BEGIN
  IF length(trim(coalesce(_customer_name, ''))) NOT BETWEEN 2 AND 100
     OR length(v_phone_digits) NOT BETWEEN 10 AND 15
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

  SELECT * INTO v_service FROM public.services WHERE id = _service_id AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Escolha um serviço ativo';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.barbers WHERE id = _barber_id AND active) THEN
    RAISE EXCEPTION 'Escolha um barbeiro ativo';
  END IF;

  SELECT * INTO v_day FROM public.schedule_settings
  WHERE barber_id = _barber_id AND weekday = extract(dow FROM _booking_date)::integer AND is_open;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dia fechado';
  END IF;

  v_requested_minutes := split_part(_booking_time, ':', 1)::integer * 60 + split_part(_booking_time, ':', 2)::integer;
  v_service_minutes := coalesce(v_service.duration_min, 30);
  v_step := greatest(5, least(coalesce(v_day.slot_min, 30), 240));

  v_in_morning :=
    v_requested_minutes >= split_part(v_day.morning_start, ':', 1)::integer * 60 + split_part(v_day.morning_start, ':', 2)::integer
    AND v_requested_minutes + v_service_minutes <= split_part(v_day.morning_end, ':', 1)::integer * 60 + split_part(v_day.morning_end, ':', 2)::integer
    AND mod(v_requested_minutes - (split_part(v_day.morning_start, ':', 1)::integer * 60 + split_part(v_day.morning_start, ':', 2)::integer), v_step) = 0;

  v_in_afternoon :=
    v_requested_minutes >= split_part(v_day.afternoon_start, ':', 1)::integer * 60 + split_part(v_day.afternoon_start, ':', 2)::integer
    AND v_requested_minutes + v_service_minutes <= split_part(v_day.afternoon_end, ':', 1)::integer * 60 + split_part(v_day.afternoon_end, ':', 2)::integer
    AND mod(v_requested_minutes - (split_part(v_day.afternoon_start, ':', 1)::integer * 60 + split_part(v_day.afternoon_start, ':', 2)::integer), v_step) = 0;

  IF NOT (v_in_morning OR v_in_afternoon) THEN
    RAISE EXCEPTION 'Horário fora do expediente ou da grade disponível';
  END IF;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.booking_rate_limits AS limits (user_id, window_started_at, window_count, updated_at)
    VALUES (v_user_id, now(), 1, now())
    ON CONFLICT (user_id) DO UPDATE
    SET
      window_started_at = CASE WHEN limits.window_started_at <= now() - interval '10 minutes' THEN now() ELSE limits.window_started_at END,
      window_count = CASE WHEN limits.window_started_at <= now() - interval '10 minutes' THEN 1 ELSE limits.window_count + 1 END,
      updated_at = now()
    RETURNING window_count INTO v_window_count;

    IF v_window_count > 5 THEN
      RAISE EXCEPTION 'Muitos agendamentos em pouco tempo. Aguarde alguns minutos.';
    END IF;
  ELSE
    -- Guests without an account: serialize per phone and cap recent and pending bookings.
    PERFORM pg_advisory_xact_lock(hashtext('guest_booking:' || v_phone_digits));
    IF (SELECT count(*) FROM public.bookings b
        WHERE b.user_id IS NULL
          AND regexp_replace(b.customer_phone, '[^0-9]', '', 'g') = v_phone_digits
          AND b.created_at > now() - interval '10 minutes') >= 3
       OR (SELECT count(*) FROM public.bookings b
        WHERE b.user_id IS NULL
          AND regexp_replace(b.customer_phone, '[^0-9]', '', 'g') = v_phone_digits
          AND b.status NOT IN ('cancelado', 'concluido')
          AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date) >= 5 THEN
      RAISE EXCEPTION 'Muitos agendamentos em pouco tempo. Aguarde alguns minutos.';
    END IF;
  END IF;

  INSERT INTO public.bookings (
    user_id, barber_id, customer_name, customer_phone, service_id,
    service_name, price, duration_min, booking_date, booking_time, notes
  )
  VALUES (
    v_user_id, _barber_id, trim(_customer_name), trim(_customer_phone), v_service.id, v_service.name,
    v_service.price, v_service_minutes, _booking_date, _booking_time, nullif(trim(coalesce(_notes, '')), '')
  )
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_booking_authenticated(uuid, text, text, uuid, date, text, text) TO anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.find_my_bookings(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_my_booking(uuid, text, text) FROM PUBLIC, anon, authenticated;