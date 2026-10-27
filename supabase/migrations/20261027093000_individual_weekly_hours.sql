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
