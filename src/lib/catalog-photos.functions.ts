import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

const PHOTO_PATH = /^(services|barbers)\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$/i;

// Public: signs a short-lived URL only for photos currently shown on an active service or barber.
export const getCatalogPhotoUrl = createServerFn({ method: "POST" })
  .inputValidator((input: unknown) => z.object({ path: z.string().max(200).regex(PHOTO_PATH) }).parse(input))
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const table = data.path.startsWith("services/") ? "services" : "barbers";
    const { data: owner } = await supabaseAdmin
      .from(table)
      .select("id")
      .eq("photo_path", data.path)
      .eq("active", true)
      .limit(1)
      .maybeSingle();
    if (!owner) return { url: null as string | null };

    const { data: signed } = await supabaseAdmin.storage
      .from("catalog-photos")
      .createSignedUrl(data.path, 3600);
    if (!signed?.signedUrl) return { url: null as string | null };
    const u = new URL(signed.signedUrl);
    return { url: `${u.pathname}${u.search}` };
  });
