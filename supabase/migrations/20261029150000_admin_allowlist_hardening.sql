-- Restrict staff-only writes to the two explicitly authorized admin accounts.
-- Public read access remains unchanged so the booking site can keep displaying availability/photos.
-- This migration does not change booking, cancellation, pricing, or schedule logic.

DO $$
BEGIN
  IF to_regclass('public.schedule_blocks') IS NOT NULL THEN
    DROP POLICY IF EXISTS blocks_staff_manage ON public.schedule_blocks;
    CREATE POLICY blocks_staff_manage
      ON public.schedule_blocks
      FOR ALL
      TO authenticated
      USING (
        lower(coalesce(auth.jwt() ->> 'email', '')) IN (
          'natanvivian39@gmail.com',
          'douglasmachadodigao@gmail.com'
        )
      )
      WITH CHECK (
        lower(coalesce(auth.jwt() ->> 'email', '')) IN (
          'natanvivian39@gmail.com',
          'douglasmachadodigao@gmail.com'
        )
      );
  END IF;
END $$;

-- Keep anonymous/public viewing of catalog images as currently configured,
-- but restrict upload, replacement and deletion to the two authorized accounts.
DROP POLICY IF EXISTS "Staff can upload catalog photos" ON storage.objects;
CREATE POLICY "Staff can upload catalog photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'catalog-photos'
    AND lower(coalesce(auth.jwt() ->> 'email', '')) IN (
      'natanvivian39@gmail.com',
      'douglasmachadodigao@gmail.com'
    )
  );

DROP POLICY IF EXISTS "Staff can replace catalog photos" ON storage.objects;
CREATE POLICY "Staff can replace catalog photos"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'catalog-photos'
    AND lower(coalesce(auth.jwt() ->> 'email', '')) IN (
      'natanvivian39@gmail.com',
      'douglasmachadodigao@gmail.com'
    )
  )
  WITH CHECK (
    bucket_id = 'catalog-photos'
    AND lower(coalesce(auth.jwt() ->> 'email', '')) IN (
      'natanvivian39@gmail.com',
      'douglasmachadodigao@gmail.com'
    )
  );

DROP POLICY IF EXISTS "Staff can delete catalog photos" ON storage.objects;
CREATE POLICY "Staff can delete catalog photos"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'catalog-photos'
    AND lower(coalesce(auth.jwt() ->> 'email', '')) IN (
      'natanvivian39@gmail.com',
      'douglasmachadodigao@gmail.com'
    )
  );
