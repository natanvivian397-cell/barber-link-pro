import { useEffect, useState } from "react";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { WEEKDAY_NAMES, todayISO, addDaysISO, type Service } from "@/lib/booking";

export function FixedClients({ barberId, onSaved }: { barberId: string; onSaved: () => void }) {
  const [services, setServices] = useState<Service[]>([]);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ name: "", phone: "", service: "", weekday: "2", time: "14:00", start: todayISO(), end: addDaysISO(todayISO(), 90) });
  useEffect(() => {
    async function load() {
      const { data } = await supabase.from("services").select("*").eq("active", true).order("sort_order");
      setServices(data ?? []);
    }
    void load();
    const channel = supabase.channel("fixed-client-services").on("postgres_changes", { event: "*", schema: "public", table: "services" }, () => void load()).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, []);
  const field = "w-full min-w-0 rounded-lg border border-border bg-background px-3 py-2 text-sm";
  const update = (key: keyof typeof form, value: string) => setForm(previous => ({ ...previous, [key]: value }));
  return <form className="space-y-4 px-6 pt-6" onSubmit={async event => {
    event.preventDefault();
    if (busy || !barberId) return;
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("book_fixed_client", { _barber: barberId, _service: form.service, _name: form.name, _phone: form.phone, _weekday: Number(form.weekday), _time: form.time, _start: form.start, _end: form.end });
      if (error) {
        toast.error(error.code === "23505" ? "Há um horário ocupado ou bloqueado no período. Nenhuma reserva foi criada; ajuste o horário ou as datas." : error.message);
        return;
      }
      toast.success(`${data} horários semanais reservados.`);
      setForm(previous => ({ ...previous, name: "", phone: "" }));
      onSaved();
    } catch { toast.error("Não foi possível reservar. Tente novamente."); }
    finally { setBusy(false); }
  }}>
    <h2 className="text-lg font-semibold">Cliente fixo</h2>
    <label className="block space-y-1 text-sm">Nome<input aria-label="Nome do cliente fixo" required minLength={2} className={field} value={form.name} onChange={e => update("name", e.target.value)} /></label>
    <label className="block space-y-1 text-sm">WhatsApp<input aria-label="WhatsApp do cliente fixo" required type="tel" className={field} value={form.phone} onChange={e => update("phone", e.target.value)} /></label>
    <label className="block space-y-1 text-sm">Serviço<select required className={field} value={form.service} onChange={e => update("service", e.target.value)}><option value="">Selecione</option>{services.map(service => <option key={service.id} value={service.id}>{service.name} · {service.duration_min} min</option>)}</select></label>
    <div className="grid grid-cols-2 gap-3">
      <label className="space-y-1 text-sm">Toda semana<select className={field} value={form.weekday} onChange={e => update("weekday", e.target.value)}>{WEEKDAY_NAMES.map((name, index) => <option key={name} value={index}>{name}</option>)}</select></label>
      <label className="space-y-1 text-sm">Horário<input required type="time" className={field} value={form.time} onChange={e => update("time", e.target.value)} /></label>
      <label className="space-y-1 text-sm">De<input required type="date" min={todayISO()} className={field} value={form.start} onChange={e => update("start", e.target.value)} /></label>
      <label className="space-y-1 text-sm">Até<input required type="date" min={form.start} max={addDaysISO(form.start, 366)} className={field} value={form.end} onChange={e => update("end", e.target.value)} /></label>
    </div>
    <Button type="submit" disabled={busy || !barberId} className="w-full"><Plus className="h-4 w-4" />{busy ? "Reservando…" : "Reservar horários semanais"}</Button>
  </form>;
}