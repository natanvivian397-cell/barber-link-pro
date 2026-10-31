-- Barber Link Pro: production security hardening.
-- Idempotent. Apply only after reviewing this migration and testing the PR preview.
-- Does not alter existing bookings, prices, barber schedules or customer records.

-- One canonical admin predicate for policy expressions. JWT email is signed by Supabase Auth.
CREATE OR REPLACE FUNCTION public.is_barber_link_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com'
  );
$$;

REVOKE ALL ON FUNCTION public.is_barber_link_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_barber_link_admin() TO authenticated;

-- Public catalog reads are required by the booking page. All writes are admin-only.
DO $$
DECLARE
  t text;
  p record;
BEGIN
  FOREACH t IN ARRAY ARRAY['barbers', 'services', 'schedule_settings'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      FOR p IN
        SELECT policyname FROM pg_policies
        WHERE schemaname = 'public' AND tablename = t
      LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, t);
      END LOOP;
      -- Remove every inherited table privilege (including TRUNCATE, which bypasses RLS),
      -- then grant only the operations the app actually needs.
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
      EXECUTE format('GRANT SELECT ON TABLE public.%I TO anon, authenticated', t);
      EXECUTE format('GRANT INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (true)',
        t || '_public_read', t
      );
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_barber_link_admin()) WITH CHECK (public.is_barber_link_admin())',
        t || '_admin_manage', t
      );
    END IF;
  END LOOP;
END $$;

-- Date blocks are visible to the public booking UI, but only the two admins may
-- create, move or delete a block. Replace permissive legacy policies.
DO $$
DECLARE p record;
BEGIN
  IF to_regclass('public.schedule_blocks') IS NOT NULL THEN
    ALTER TABLE public.schedule_blocks ENABLE ROW LEVEL SECURITY;
    FOR p IN SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'schedule_blocks'
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.schedule_blocks', p.policyname);
    END LOOP;
    -- TRUNCATE bypasses RLS, so revoke all inherited privileges before granting the minimum.
    REVOKE ALL ON TABLE public.schedule_blocks FROM PUBLIC, anon, authenticated;
    GRANT SELECT ON TABLE public.schedule_blocks TO anon, authenticated;
    GRANT INSERT, UPDATE, DELETE ON TABLE public.schedule_blocks TO authenticated;
    CREATE POLICY schedule_blocks_public_read
      ON public.schedule_blocks FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY schedule_blocks_admin_manage
      ON public.schedule_blocks FOR ALL TO authenticated
      USING (public.is_barber_link_admin())
      WITH CHECK (public.is_barber_link_admin());
  END IF;
END $$;

-- Optional date-closure table exists only in deployments that applied its migration.
DO $$
DECLARE p record;
BEGIN
  IF to_regclass('public.booking_blocked_dates') IS NOT NULL THEN
    ALTER TABLE public.booking_blocked_dates ENABLE ROW LEVEL SECURITY;
    FOR p IN SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'booking_blocked_dates'
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.booking_blocked_dates', p.policyname);
    END LOOP;
    -- TRUNCATE bypasses RLS, so revoke all inherited privileges before granting the minimum.
    REVOKE ALL ON TABLE public.booking_blocked_dates FROM PUBLIC, anon, authenticated;
    GRANT SELECT ON TABLE public.booking_blocked_dates TO anon, authenticated;
    GRANT INSERT, UPDATE, DELETE ON TABLE public.booking_blocked_dates TO authenticated;
    CREATE POLICY booking_blocked_dates_public_read
      ON public.booking_blocked_dates FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY booking_blocked_dates_admin_manage
      ON public.booking_blocked_dates FOR ALL TO authenticated
      USING (public.is_barber_link_admin())
      WITH CHECK (public.is_barber_link_admin());
  END IF;
END $$;

-- The storage catalog remains publicly readable. Even if an older broad
-- permissive policy exists, restrictive policies require admin identity for
-- writes to the catalog-photos bucket.
DROP POLICY IF EXISTS catalog_photos_admin_insert_guard ON storage.objects;
CREATE POLICY catalog_photos_admin_insert_guard
  ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (bucket_id <> 'catalog-photos' OR public.is_barber_link_admin());

DROP POLICY IF EXISTS catalog_photos_admin_update_guard ON storage.objects;
CREATE POLICY catalog_photos_admin_update_guard
  ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (bucket_id <> 'catalog-photos' OR public.is_barber_link_admin())
  WITH CHECK (bucket_id <> 'catalog-photos' OR public.is_barber_link_admin());

DROP POLICY IF EXISTS catalog_photos_admin_delete_guard ON storage.objects;
CREATE POLICY catalog_photos_admin_delete_guard
  ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
  USING (bucket_id <> 'catalog-photos' OR public.is_barber_link_admin());

-- RLS does not protect TRUNCATE. Remove inherited table privileges on bookings,
-- then restore only the customer/admin operations explicitly designed above.
REVOKE ALL ON TABLE public.bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.bookings TO authenticated;
GRANT UPDATE (status) ON TABLE public.bookings TO authenticated;

-- Ensure manual schedule blocks are enforced by the database, not only by the UI.
-- Recreate these guards here because the original definitions live in the legacy
-- Drizzle migration and may not be present in every Lovable Cloud deployment.
CREATE OR REPLACE FUNCTION public.prevent_booking_in_block()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_start integer;
BEGIN
  IF NEW.status = 'cancelado' OR NEW.barber_id IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(NEW.barber_id::text || NEW.booking_date::text));
  v_start := split_part(NEW.booking_time, ':', 1)::integer * 60
           + split_part(NEW.booking_time, ':', 2)::integer;

  IF EXISTS (
    SELECT 1
    FROM public.schedule_blocks AS sb
    WHERE sb.barber_id = NEW.barber_id
      AND sb.booking_date = NEW.booking_date
      AND (split_part(sb.booking_time, ':', 1)::integer * 60
           + split_part(sb.booking_time, ':', 2)::integer) < v_start + NEW.duration_min
      AND (split_part(sb.booking_time, ':', 1)::integer * 60
           + split_part(sb.booking_time, ':', 2)::integer) + sb.duration_min > v_start
  ) THEN
    RAISE EXCEPTION 'Horário bloqueado' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_block_on_booking()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_start integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(NEW.barber_id::text || NEW.booking_date::text));
  v_start := split_part(NEW.booking_time, ':', 1)::integer * 60
           + split_part(NEW.booking_time, ':', 2)::integer;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS b
    WHERE b.barber_id = NEW.barber_id
      AND b.booking_date = NEW.booking_date
      AND b.status <> 'cancelado'
      AND (split_part(b.booking_time, ':', 1)::integer * 60
           + split_part(b.booking_time, ':', 2)::integer) < v_start + NEW.duration_min
      AND (split_part(b.booking_time, ':', 1)::integer * 60
           + split_part(b.booking_time, ':', 2)::integer) + b.duration_min > v_start
  ) THEN
    RAISE EXCEPTION 'Horário já agendado' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.schedule_blocks') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS bookings_reject_block ON public.bookings;
    CREATE TRIGGER bookings_reject_block
      BEFORE INSERT OR UPDATE ON public.bookings
      FOR EACH ROW EXECUTE FUNCTION public.prevent_booking_in_block();

    DROP TRIGGER IF EXISTS blocks_reject_bookings ON public.schedule_blocks;
    CREATE TRIGGER blocks_reject_bookings
      BEFORE INSERT OR UPDATE ON public.schedule_blocks
      FOR EACH ROW EXECUTE FUNCTION public.prevent_block_on_booking();
  END IF;
END;
$$;

-- Customer booking RPC: enforce the same 30-day horizon as the UI at the
-- database boundary, not merely in browser code. Canonical service data is
-- always loaded from the database; user_id always comes from auth.uid().
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

  -- Enforce recurring closure dates on the server even if the browser is bypassed.
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

-- Keep public availability minimal and bounded to the same customer booking window.
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
    AND b.booking_date BETWEEN
      (now() AT TIME ZONE 'America/Sao_Paulo')::date
      AND (now() AT TIME ZONE 'America/Sao_Paulo')::date + 30
    AND b.status <> 'cancelado'
$$;

REVOKE ALL ON FUNCTION public.get_public_booking_slots(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_booking_slots(uuid, date) TO anon, authenticated;

-- Enforce recurring closure dates for every insertion/update path, including
-- admin-created and recurring reservations. Existing date-specific block
-- trigger remains in place if the optional blocked-dates table is installed.
CREATE OR REPLACE FUNCTION public.prevent_recurring_holiday_booking()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status <> 'cancelado'
     AND to_char(NEW.booking_date, 'MM-DD') IN ('12-24','12-25','12-26','12-31','01-01','01-02') THEN
    RAISE EXCEPTION 'Barbearia fechada nesta data' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_prevent_recurring_holiday ON public.bookings;
CREATE TRIGGER bookings_prevent_recurring_holiday
BEFORE INSERT OR UPDATE OF booking_date ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.prevent_recurring_holiday_booking();

-- If the optional date-block migration is installed, narrow its legacy trigger
-- to inserts and booking-date changes. Status-only updates (e.g. completing an
-- older reservation) must remain possible even when its date is a closure.
DO $
BEGIN
  IF to_regclass('public.booking_blocked_dates') IS NOT NULL
     AND to_regprocedure('public.prevent_booking_on_blocked_date()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS bookings_reject_blocked_dates ON public.bookings;
    CREATE TRIGGER bookings_reject_blocked_dates
      BEFORE INSERT OR UPDATE OF booking_date ON public.bookings
      FOR EACH ROW EXECUTE FUNCTION public.prevent_booking_on_blocked_date();
  END IF;
END;
$;

-- Explicitly preserve the admin allowlist on Storage write policies.
DROP POLICY IF EXISTS "Staff can upload catalog photos" ON storage.objects;
CREATE POLICY "Staff can upload catalog photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'catalog-photos' AND public.is_barber_link_admin()
  );

DROP POLICY IF EXISTS "Staff can replace catalog photos" ON storage.objects;
CREATE POLICY "Staff can replace catalog photos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'catalog-photos' AND public.is_barber_link_admin()
  )
  WITH CHECK (
    bucket_id = 'catalog-photos' AND public.is_barber_link_admin()
  );

DROP POLICY IF EXISTS "Staff can delete catalog photos" ON storage.objects;
CREATE POLICY "Staff can delete catalog photos"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'catalog-photos' AND public.is_barber_link_admin()
  );

COMMENT ON FUNCTION public.create_booking_authenticated(uuid, text, text, uuid, date, text, text)
IS 'Creates an authenticated customer booking with server-side ownership, date horizon, holiday, schedule and canonical service validation.';
