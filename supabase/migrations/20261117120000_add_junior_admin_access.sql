-- Add Júnior's existing account to the server-side admin allowlist.
-- Preserve all existing authorization boundaries and customer ownership rules.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_barber_link_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT lower(coalesce(auth.jwt() ->> 'email', '')) IN (
    'natanvivian39@gmail.com',
    'douglasmachadodigao@gmail.com',
    'juniorjosias2018@gmail.com'
  );
$$;

REVOKE ALL ON FUNCTION public.is_barber_link_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_barber_link_admin() TO authenticated;

-- Keep customer ownership intact while allowing all three admins to manage bookings.
DROP POLICY IF EXISTS bookings_select_owner_or_admin ON public.bookings;
CREATE POLICY bookings_select_owner_or_admin
ON public.bookings FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR public.is_barber_link_admin()
);

DROP POLICY IF EXISTS bookings_insert_admin_only ON public.bookings;
CREATE POLICY bookings_insert_admin_only
ON public.bookings FOR INSERT TO authenticated
WITH CHECK (public.is_barber_link_admin());

DROP POLICY IF EXISTS bookings_update_owner_or_admin ON public.bookings;
CREATE POLICY bookings_update_owner_or_admin
ON public.bookings FOR UPDATE TO authenticated
USING (
  (
    user_id = (SELECT auth.uid())
    AND status NOT IN ('concluido', 'cancelado')
  )
  OR public.is_barber_link_admin()
)
WITH CHECK (
  (
    user_id = (SELECT auth.uid())
    AND status = 'cancelado'
  )
  OR public.is_barber_link_admin()
);

DROP POLICY IF EXISTS bookings_delete_admin_only ON public.bookings;
CREATE POLICY bookings_delete_admin_only
ON public.bookings FOR DELETE TO authenticated
USING (public.is_barber_link_admin());

COMMIT;
