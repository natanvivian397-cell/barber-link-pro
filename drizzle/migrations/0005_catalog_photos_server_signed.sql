-- Visitors now get catalog photo links from the server, which only signs photos used by active services/barbers.
-- Direct storage reads are limited to the panel admins ("Staff can view catalog photos").
DROP POLICY IF EXISTS "Catalog photos can be viewed" ON storage.objects;