-- Public visitors only see what the booking page needs; admins keep full access via existing *_admin_manage policies.
DROP POLICY IF EXISTS barbers_public_read ON public.barbers;
CREATE POLICY barbers_public_read ON public.barbers
  FOR SELECT TO anon, authenticated
  USING (active);

DROP POLICY IF EXISTS services_public_read ON public.services;
CREATE POLICY services_public_read ON public.services
  FOR SELECT TO anon, authenticated
  USING (active);

DROP POLICY IF EXISTS schedule_settings_public_read ON public.schedule_settings;
CREATE POLICY schedule_settings_public_read ON public.schedule_settings
  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM public.barbers b
    WHERE b.id = schedule_settings.barber_id AND b.active
  ));

DROP POLICY IF EXISTS schedule_blocks_public_read ON public.schedule_blocks;
CREATE POLICY schedule_blocks_public_read ON public.schedule_blocks
  FOR SELECT TO anon, authenticated
  USING (
    booking_date BETWEEN (now() AT TIME ZONE 'America/Sao_Paulo')::date
                     AND (now() AT TIME ZONE 'America/Sao_Paulo')::date + 30
    AND EXISTS (
      SELECT 1 FROM public.barbers b
      WHERE b.id = schedule_blocks.barber_id AND b.active
    )
  );

-- Catalog photos: visitors can only read files currently used by an active service or barber.
DROP POLICY IF EXISTS "Catalog photos can be viewed" ON storage.objects;
CREATE POLICY "Catalog photos can be viewed" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (
    bucket_id = 'catalog-photos'
    AND (
      EXISTS (SELECT 1 FROM public.services s WHERE s.active AND s.photo_path = objects.name)
      OR EXISTS (SELECT 1 FROM public.barbers b WHERE b.active AND b.photo_path = objects.name)
    )
  );

DROP POLICY IF EXISTS "Staff can view catalog photos" ON storage.objects;
CREATE POLICY "Staff can view catalog photos" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'catalog-photos' AND public.is_barber_link_admin());