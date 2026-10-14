CREATE OR REPLACE FUNCTION public.find_my_bookings(_name text, _phone text)
RETURNS TABLE(id uuid, service_name text, booking_date date, booking_time text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b.id, b.service_name, b.booking_date, b.booking_time FROM bookings b
  WHERE lower(trim(b.customer_name)) = lower(trim(_name))
    AND regexp_replace(b.customer_phone, '\D', '', 'g') = regexp_replace(_phone, '\D', '', 'g')
    AND length(regexp_replace(_phone, '\D', '', 'g')) >= 10
    AND b.status NOT IN ('cancelado','concluido')
    AND b.booking_date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
  ORDER BY b.booking_date, b.booking_time
$$;
CREATE OR REPLACE FUNCTION public.cancel_my_booking(_id uuid, _name text, _phone text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n int;
BEGIN
  UPDATE bookings SET status = 'cancelado'
  WHERE id = _id AND id IN (SELECT f.id FROM find_my_bookings(_name, _phone) f);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n > 0;
END $$;
GRANT EXECUTE ON FUNCTION public.find_my_bookings(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_my_booking(uuid, text, text) TO anon, authenticated;