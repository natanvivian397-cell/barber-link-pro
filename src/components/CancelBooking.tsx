import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { formatDateBR } from "@/lib/booking";

type Found = { id: string; service_name: string; booking_date: string; booking_time: string };

export function CancelBooking() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [list, setList] = useState<Found[] | null>(null);
  const [busy, setBusy] = useState(false);

  async function search() {
    if (name.trim().length < 2 || phone.replace(/\D/g, "").length < 10) {
      toast.error("Informe o nome e o WhatsApp usados no agendamento.");
      return;
    }
    setBusy(true);
    const { data, error } = await supabase.rpc("find_my_bookings", { _name: name, _phone: phone });
    setBusy(false);
    if (error) return toast.error("Não foi possível buscar. Tente novamente.");
    setList((data ?? []) as Found[]);
  }

  async function cancel(b: Found) {
    if (!confirm(`Cancelar ${b.service_name} em ${formatDateBR(b.booking_date)} às ${b.booking_time}?`)) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("cancel_my_booking", { _id: b.id, _name: name, _phone: phone });
    setBusy(false);
    if (error || !data) return toast.error("Não foi possível cancelar.");
    toast.success("Horário cancelado.");
    setList((l) => (l ?? []).filter((x) => x.id !== b.id));
  }

  if (!open)
    return (
      <button type="button" onClick={() => setOpen(true)} className="mt-6 w-full text-center text-xs uppercase tracking-[0.2em] text-muted-foreground underline underline-offset-4 hover:text-gold">
        Cancelar um agendamento
      </button>
    );

  return (
    <section className="mt-8 space-y-3 rounded-2xl border border-border bg-card p-5">
      <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">Cancelar agendamento</h2>
      <input aria-label="Nome do agendamento" value={name} onChange={(e) => setName(e.target.value)} placeholder="Nome usado no agendamento" className="w-full rounded-full border border-border bg-background px-5 py-3 text-sm outline-none focus:border-gold" />
      <input aria-label="WhatsApp do agendamento" value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" placeholder="WhatsApp usado no agendamento" className="w-full rounded-full border border-border bg-background px-5 py-3 text-sm outline-none focus:border-gold" />
      <div className="flex gap-2">
        <Button type="button" onClick={search} disabled={busy} className="flex-1 rounded-full bg-gold text-gold-foreground hover:bg-gold/90">Buscar meus horários</Button>
        <Button type="button" variant="outline" onClick={() => { setOpen(false); setList(null); }} className="rounded-full">Fechar</Button>
      </div>
      {list && list.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum horário pendente encontrado.</p> : null}
      {list?.map((b) => (
        <div key={b.id} className="flex items-center justify-between gap-3 rounded-xl border border-border px-4 py-3 text-sm">
          <span>{b.service_name} · {formatDateBR(b.booking_date)} às {b.booking_time}</span>
          <Button type="button" variant="outline" size="sm" disabled={busy} onClick={() => cancel(b)} className="rounded-full border-destructive text-destructive">Cancelar</Button>
        </div>
      ))}
    </section>
  );
}
