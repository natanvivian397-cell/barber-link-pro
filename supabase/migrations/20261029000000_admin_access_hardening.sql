-- Security hardening: centralize admin authorization in the database.
-- Admin access is based on the verified email claim in the Supabase Auth JWT,
-- never on user-editable user_metadata.
CREATE TABLE IF NOT EXISTS public.admin_allowlist (
  email text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_allowlist_email_lowercase CHECK (email = lower(trim(email)))
);

INSERT INTO public.admin_allowlist (email) VALUES
  ('douglasmachadodigao@gmail.com'),
  ('natanyvivian39@gmail.com')
ON CONFLICT (email) DO NOTHING;

ALTER TABLE public.admin_allowlist ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.admin_allowlist FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.admin_allowlist TO service_role;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_allowlist a
    WHERE a.email = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Schedule blocks: only allowlisted administrators may create/change/delete.
DROP POLICY IF EXISTS blocks_staff_manage ON public.schedule_blocks;
DROP POLICY IF EXISTS schedule_blocks_admin_manage ON public.schedule_blocks;
CREATE POLICY schedule_blocks_admin_manage
  ON public.schedule_blocks
  FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Catalog photos remain publicly readable, but only allowlisted admins may write.
DROP POLICY IF EXISTS "Staff can upload catalog photos" ON storage.objects;
DROP POLICY IF EXISTS "Staff can replace catalog photos" ON storage.objects;
DROP POLICY IF EXISTS "Staff can delete catalog photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload catalog photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can replace catalog photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete catalog photos" ON storage.objects;

CREATE POLICY "Admins can upload catalog photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'catalog-photos' AND public.is_admin());
CREATE POLICY "Admins can replace catalog photos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'catalog-photos' AND public.is_admin())
  WITH CHECK (bucket_id = 'catalog-photos' AND public.is_admin());
CREATE POLICY "Admins can delete catalog photos"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'catalog-photos' AND public.is_admin());

-- Core table policies and public booking creation are hardened in the next migration.
-- Customer cancellation still uses name + phone as proof of ownership in the legacy
-- public RPC. For stronger assurance, replace this with an OTP verification flow before
-- claiming full account-level security; do not expose the booking table directly.
