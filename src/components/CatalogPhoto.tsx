import { useEffect, useState, type ChangeEvent } from "react";
import { ImagePlus, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { getCatalogPhotoUrl } from "@/lib/catalog-photos.functions";

const BUCKET = "catalog-photos";
const MAX_PHOTO_SIZE = 5 * 1024 * 1024;
const ALLOWED_PHOTO_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/avif": "avif",
};

const urlCache = new Map<string, Promise<string | undefined>>();

function loadPhotoUrl(path: string) {
  let pending = urlCache.get(path);
  if (!pending) {
    pending = (async () => {
      // Visitors: the server signs only photos in use by an active service or barber.
      try {
        const { url } = await getCatalogPhotoUrl({ data: { path } });
        if (url) return `${import.meta.env['VITE_SUPABASE_URL']}${url}`;
      } catch {
        // fall through to the staff path
      }
      // Staff: storage rules allow admins to read every catalog photo.
      const { data } = await supabase.storage.from(BUCKET).createSignedUrl(path, 3600);
      return data?.signedUrl;
    })();
    urlCache.set(path, pending);
    pending.then((u) => { if (!u) urlCache.delete(path); });
  }
  return pending;
}

export function CatalogPhoto({ path, alt, className = "" }: { path: string | null; alt: string; className?: string }) {
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    let current = true;
    setUrl(undefined);
    if (path) {
      loadPhotoUrl(path).then((u) => {
        if (current) setUrl(u);
      });
    }
    return () => { current = false; };
  }, [path]);
  return url ? <img src={url} alt={alt} className={className} /> : null;
}

export function CatalogPhotoUpload({ table, id, path, onSaved }: {
  table: "services" | "barbers";
  id: string;
  path: string | null;
  onSaved: () => void;
}) {
  const [busy, setBusy] = useState(false);

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    event.target.value = "";
    const extension = ALLOWED_PHOTO_TYPES[file.type];
    if (!extension || file.size === 0 || file.size > MAX_PHOTO_SIZE) {
      toast.error("Escolha uma foto JPG, PNG, WebP ou AVIF de até 5 MB.");
      return;
    }
    setBusy(true);
    const next = `${table}/${id}/${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await supabase.storage.from(BUCKET).upload(next, file, {
      contentType: file.type,
      upsert: false,
    });
    if (uploadError) {
      toast.error("Não foi possível enviar a foto.");
      setBusy(false);
      return;
    }
    const { error } = table === "services"
      ? await supabase.from("services").update({ photo_path: next }).eq("id", id)
      : await supabase.from("barbers").update({ photo_path: next }).eq("id", id);
    if (error) {
      await supabase.storage.from(BUCKET).remove([next]);
      toast.error("Não foi possível salvar a foto.");
    } else {
      if (path) await supabase.storage.from(BUCKET).remove([path]);
      onSaved();
    }
    setBusy(false);
  }

  async function remove() {
    if (!path) return;
    setBusy(true);
    const { error } = table === "services"
      ? await supabase.from("services").update({ photo_path: null }).eq("id", id)
      : await supabase.from("barbers").update({ photo_path: null }).eq("id", id);
    if (error) toast.error("Não foi possível remover a foto.");
    else {
      await supabase.storage.from(BUCKET).remove([path]);
      onSaved();
    }
    setBusy(false);
  }

  return (
    <div className="flex items-center gap-3">
      <div className="h-16 w-16 shrink-0 overflow-hidden rounded-md bg-muted">
        <CatalogPhoto path={path} alt="Foto cadastrada" className="h-full w-full object-cover" />
      </div>
      <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-foreground">
        {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ImagePlus className="h-4 w-4" />}
        {path ? "Trocar foto" : "Adicionar foto"}
        <input type="file" accept="image/jpeg,image/png,image/webp,image/avif" className="sr-only" disabled={busy} onChange={upload} />
      </label>
      {path ? <Button type="button" variant="ghost" size="sm" onClick={remove} disabled={busy}>Remover foto</Button> : null}
    </div>
  );
}