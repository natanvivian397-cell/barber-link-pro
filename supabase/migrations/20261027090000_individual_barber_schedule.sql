-- Give each barber independent weekly working hours.
BEGIN;

CREATE TEMP TABLE schedule_settings_legacy ON COMMIT DROP AS
SELECT weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min
FROM public.schedule_settings;

ALTER TABLE public.schedule_settings ADD COLUMN IF NOT EXISTS barber_id uuid;

DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.schedule_settings'::regclass
      AND contype IN ('p', 'u')
  LOOP
    EXECUTE format('ALTER TABLE public.schedule_settings DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

DELETE FROM public.schedule_settings;

ALTER TABLE public.schedule_settings
  ADD CONSTRAINT schedule_settings_barber_id_fkey
  FOREIGN KEY (barber_id) REFERENCES public.barbers(id) ON DELETE CASCADE;

INSERT INTO public.schedule_settings
  (barber_id, weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min)
SELECT b.id, s.weekday, s.is_open, s.morning_start, s.morning_end,
       s.afternoon_start, s.afternoon_end, s.slot_min
FROM public.barbers b
CROSS JOIN schedule_settings_legacy s;

ALTER TABLE public.schedule_settings ALTER COLUMN barber_id SET NOT NULL;
ALTER TABLE public.schedule_settings
  ADD CONSTRAINT schedule_settings_pkey PRIMARY KEY (barber_id, weekday);

CREATE OR REPLACE FUNCTION public.initialize_barber_schedule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.schedule_settings
    (barber_id, weekday, is_open, morning_start, morning_end, afternoon_start, afternoon_end, slot_min)
  SELECT NEW.id, s.weekday, s.is_open, s.morning_start, s.morning_end,
         s.afternoon_start, s.afternoon_end, s.slot_min
  FROM public.schedule_settings s
  WHERE s.barber_id = (
    SELECT b.id FROM public.barbers b
    WHERE b.id <> NEW.id
    ORDER BY b.sort_order, b.created_at
    LIMIT 1
  )
  ON CONFLICT (barber_id, weekday) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS barbers_initialize_schedule ON public.barbers;
CREATE TRIGGER barbers_initialize_schedule
AFTER INSERT ON public.barbers
FOR EACH ROW EXECUTE FUNCTION public.initialize_barber_schedule();

COMMIT;
