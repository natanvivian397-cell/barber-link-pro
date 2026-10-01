import { useEffect, useState, type ChangeEvent } from "react";
import { ImagePlus, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";

const BUCKET = "catalog-photos";

export function CatalogPhoto({ path, alt, className = "" }: { path: string | null; alt: string; className?: string }) {
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    let current = true;
    setUrl(undefined);
    if (path) {
      supabase.storage.from(BUCKET).createSignedUrl(path, 3600).then(({ data }) => {
        if (current) setUrl(data?.signedUrl);
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
    if (!file.type.startsWith("image/") || file.size > 5 * 1024 * 1024) {
      toast.error("Escolha uma foto de até 5 MB.");
      return;
    }
    setBusy(true);
    const next = `${table}/${id}/${crypto.randomUUID()}.${file.name.split(".").pop()?.toLowerCase() || "jpg"}`;
    const { error: uploadError } = await supabase.storage.from(BUCKET).upload(next, file, { contentType: file.type });
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
        <input type="file" accept="image/*" className="sr-only" disabled={busy} onChange={upload} />
      </label>
      {path ? <Button type="button" variant="ghost" size="sm" onClick={remove} disabled={busy}>Remover foto</Button> : null}
    </div>
  );
}