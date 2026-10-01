ALTER TABLE public.services ADD COLUMN photo_path text;
ALTER TABLE public.barbers ADD COLUMN photo_path text;
CREATE POLICY "Catalog photos can be viewed" ON storage.objects FOR SELECT TO anon, authenticated USING (bucket_id = 'catalog-photos');
CREATE POLICY "Staff can upload catalog photos" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'catalog-photos');
CREATE POLICY "Staff can replace catalog photos" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'catalog-photos') WITH CHECK (bucket_id = 'catalog-photos');
CREATE POLICY "Staff can delete catalog photos" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'catalog-photos');