CREATE OR REPLACE FUNCTION public.book_fixed_client(_barber uuid, _service uuid, _name text, _phone text, _weekday integer, _time text, _start date, _end date)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE svc public.services%ROWTYPE; day public.schedule_settings%ROWTYPE; d date; n integer := 0; minutes integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no painel'; END IF;
 IF length(trim(_name)) < 2 OR length(regexp_replace(_phone, '\D', '', 'g')) < 10 THEN RAISE EXCEPTION 'Informe nome e WhatsApp'; END IF;
 IF _weekday NOT BETWEEN 0 AND 6 OR _start IS NULL OR _end IS NULL OR _start < (now() AT TIME ZONE 'America/Sao_Paulo')::date OR _end < _start OR _end > _start + 366 THEN RAISE EXCEPTION 'Escolha um período futuro de até um ano'; END IF;
 IF _time IS NULL OR _time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Horário inválido'; END IF;
 SELECT * INTO svc FROM public.services WHERE id = _service AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escolha um serviço ativo'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.barbers WHERE id = _barber AND active) THEN RAISE EXCEPTION 'Escolha um barbeiro ativo'; END IF;
 SELECT * INTO day FROM public.schedule_settings WHERE weekday = _weekday AND is_open;
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