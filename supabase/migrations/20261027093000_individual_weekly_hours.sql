-- Make weekly working hours independent per barber without deleting existing settings.
BEGIN;

CREATE TEMP TABLE schedule_settings_backup ON COMMIT DROP AS
SELECT weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min
FROM public.schedule_settings;

ALTER TABLE public.schedule_settings
  ADD COLUMN IF NOT EXISTS barber_id uuid;

DO $$
DECLARE
  first_barber_id uuid;
  pk_name text;
BEGIN
  SELECT id INTO first_barber_id
  FROM public.barbers
  ORDER BY sort_order, created_at
  LIMIT 1;

  IF first_barber_id IS NULL THEN
    RAISE EXCEPTION 'Cannot scope schedule_settings: no barbers exist';
  END IF;

  UPDATE public.schedule_settings
  SET barber_id = first_barber_id
  WHERE barber_id IS NULL;

  SELECT conname INTO pk_name
  FROM pg_constraint
  WHERE conrelid = 'public.schedule_settings'::regclass
    AND contype = 'p'
  LIMIT 1;

  IF pk_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.schedule_settings DROP CONSTRAINT %I', pk_name);
  END IF;
END $$;

-- Give every existing barber a copy of the current schedule as a safe starting point.
INSERT INTO public.schedule_settings
  (barber_id, weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min)
SELECT b.id, s.weekday, s.is_open, s.morning_start, s.morning_end,
       s.afternoon_start, s.afternoon_end, s.slot_min
FROM public.barbers b
CROSS JOIN schedule_settings_backup s
WHERE NOT EXISTS (
  SELECT 1 FROM public.schedule_settings existing
  WHERE existing.barber_id = b.id AND existing.weekday = s.weekday
);

ALTER TABLE public.schedule_settings
  ALTER COLUMN barber_id SET NOT NULL;

ALTER TABLE public.schedule_settings
  ADD CONSTRAINT schedule_settings_pkey PRIMARY KEY (barber_id, weekday);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.schedule_settings'::regclass
      AND conname = 'schedule_settings_barber_id_fkey'
  ) THEN
    ALTER TABLE public.schedule_settings
      ADD CONSTRAINT schedule_settings_barber_id_fkey
      FOREIGN KEY (barber_id) REFERENCES public.barbers(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.initialize_barber_schedule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_barber_id uuid;
BEGIN
  SELECT id INTO source_barber_id
  FROM public.barbers
  WHERE id <> NEW.id
  ORDER BY sort_order, created_at
  LIMIT 1;

  IF source_barber_id IS NOT NULL THEN
    INSERT INTO public.schedule_settings
      (barber_id, weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min)
    SELECT NEW.id, weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min
    FROM public.schedule_settings
    WHERE barber_id = source_barber_id
    ON CONFLICT (barber_id, weekday) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS barbers_initialize_schedule ON public.barbers;
CREATE TRIGGER barbers_initialize_schedule
AFTER INSERT ON public.barbers
FOR EACH ROW EXECUTE FUNCTION public.initialize_barber_schedule();

COMMIT;

-- Keep recurring bookings restricted to the selected barber's own weekly schedule.
CREATE OR REPLACE FUNCTION public.book_fixed_client(_barber uuid, _service uuid, _name text, _phone text, _weekday integer, _time text, _start date, _end date)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE svc public.services%ROWTYPE; day public.schedule_settings%ROWTYPE; d date; n integer := 0; minutes integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no painel'; END IF;
 IF length(trim(_name)) < 2 OR length(regexp_replace(_phone, '\\D', '', 'g')) < 10 THEN RAISE EXCEPTION 'Informe nome e WhatsApp'; END IF;
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
