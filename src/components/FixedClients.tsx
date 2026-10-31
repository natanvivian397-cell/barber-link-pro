import { useCallback, useEffect, useMemo, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { WEEKDAY_NAMES, todayISO, addDaysISO, type Service } from "@/lib/booking";

type FixedBooking = {
  id: string; barber_id: string; customer_name: string; customer_phone: string;
  service_name: string; booking_date: string; booking_time: string; status: string; notes: string | null;
};
type FixedClientGroup = {
  key: string; name: string; phone: string; service: string; time: string; weekday: number;
  bookings: FixedBooking[]; activeCount: number;
};
const FIXED_CLIENT_NOTE = "Cliente fixo · semanal";

export function FixedClients({ barberId, onSaved }: { barberId: string; onSaved: () => void }) {
  const [services, setServices] = useState<Service[]>([]);
  const [fixedBookings, setFixedBookings] = useState<FixedBooking[]>([]);
  const [busy, setBusy] = useState(false);
  const [deletingKey, setDeletingKey] = useState<string | null>(null);
  const [loadingClients, setLoadingClients] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: "", phone: "", service: "", weekday: "2", time: "14:00", start: todayISO(), end: addDaysISO(todayISO(), 90) });

  const loadFixedClients = useCallback(async () => {
    if (!barberId) { setFixedBookings([]); setLoadingClients(false); return; }
    setLoadingClients(true);
    const { data, error } = await supabase.from("bookings")
      .select("id, barber_id, customer_name, customer_phone, service_name, booking_date, booking_time, status, notes")
      .eq("barber_id", barberId).eq("notes", FIXED_CLIENT_NOTE)
      .gte("booking_date", todayISO()).order("booking_date", { ascending: true });
    if (error) toast.error("Não foi possível carregar os clientes fixos.");
    else setFixedBookings((data ?? []) as FixedBooking[]);
    setLoadingClients(false);
  }, [barberId]);

  useEffect(() => {
    async function loadServices() {
      const { data } = await supabase.from("services").select("*").eq("active", true).order("sort_order");
      setServices(data ?? []);
    }
    void loadServices();
    const channel = supabase.channel("fixed-client-services")
      .on("postgres_changes", { event: "*", schema: "public", table: "services" }, () => void loadServices()).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, []);

  useEffect(() => {
    void loadFixedClients();
    const channel = supabase.channel(`fixed-clients-${barberId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "bookings", filter: `barber_id=eq.${barberId}` }, () => void loadFixedClients())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [barberId, loadFixedClients]);

  const groups = useMemo<FixedClientGroup[]>(() => {
    const grouped = new Map<string, FixedClientGroup>();
    for (const booking of fixedBookings) {
      const weekday = new Date(`${booking.booking_date}T12:00:00`).getDay();
      const normalizedPhone = booking.customer_phone.replace(/\D/g, "");
      const key = JSON.stringify([booking.customer_name.trim().toLocaleLowerCase(), normalizedPhone, booking.service_name, booking.booking_time, weekday]);
      const existing = grouped.get(key);
      if (existing) {
        existing.bookings.push(booking);
        if (booking.status !== "cancelado") existing.activeCount += 1;
      } else {
        grouped.set(key, { key, name: booking.customer_name, phone: booking.customer_phone, service: booking.service_name,
          time: booking.booking_time, weekday, bookings: [booking], activeCount: booking.status === "cancelado" ? 0 : 1 });
      }
    }
    return Array.from(grouped.values()).filter(group => group.activeCount > 0)
      .sort((a, b) => a.name.localeCompare(b.name, "pt-BR"));
  }, [fixedBookings]);

  const field = "w-full min-w-0 rounded-lg border border-border bg-background px-3 py-2 text-sm";
  const update = (key: keyof typeof form, value: string) => setForm(previous => ({ ...previous, [key]: value }));

  async function removeFixedClient(group: FixedClientGroup) {
    if (!confirm(`Excluir o cliente fixo ${group.name}? Todos os ${group.bookings.length} horários futuros desse cadastro na agenda atual serão removidos. Os atendimentos passados e a agenda do outro barbeiro serão preservados.`)) return;
    setDeletingKey(group.key);
    const { error } = await supabase.from("bookings").delete()
      .in("id", group.bookings.map(booking => booking.id)).eq("barber_id", barberId);
    setDeletingKey(null);
    if (error) { toast.error("Não foi possível excluir esse cliente fixo."); return; }
    toast.success(`Cliente fixo ${group.name} excluído da agenda.`);
    await loadFixedClients();
  }

  return (
    <div className="space-y-6 px-6 pt-6 pb-6">
      <section className="space-y-3 rounded-2xl border border-border bg-card p-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">Clientes fixos</h2>
            <p className="text-xs text-muted-foreground">
              {groups.length} {groups.length === 1 ? "cliente cadastrado" : "clientes cadastrados"} nesta agenda
            </p>
          </div>
          <span className="rounded-full bg-muted px-3 py-1 text-xs font-semibold">{groups.length}</span>
        </div>
        <div className="space-y-3">
          {loadingClients ? <p className="py-4 text-center text-sm text-muted-foreground">Carregando clientes fixos…</p>
            : groups.length === 0 ? (
              <div className="rounded-xl border border-dashed border-border px-4 py-6 text-center">
                <p className="text-sm font-medium">Nenhum cliente fixo ativo</p>
                <p className="mt-1 text-xs text-muted-foreground">Cadastre o primeiro cliente pelo botão abaixo.</p>
              </div>
            ) : groups.map(group => (
              <div key={group.key} className="flex items-center justify-between gap-3 rounded-xl border border-border p-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold">{group.name}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">{group.phone}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{group.service} · {WEEKDAY_NAMES[group.weekday]} às {group.time}</p>
                  <p className="mt-1 text-xs font-medium">{group.activeCount} horário(s) futuro(s) ativo(s)</p>
                </div>
                <button type="button" onClick={() => void removeFixedClient(group)} disabled={deletingKey === group.key}
                  aria-label={`Excluir cliente fixo ${group.name}`}
                  className="flex shrink-0 items-center gap-1.5 rounded-full border border-destructive/30 px-3 py-2 text-xs font-semibold text-destructive disabled:opacity-50">
                  <Trash2 className="h-3.5 w-3.5" />{deletingKey === group.key ? "Excluindo…" : "Excluir"}
                </button>
              </div>
            ))}
        </div>
      </section>

      <section className="rounded-2xl border border-border bg-card p-4">
        <div className="space-y-2">
          <div>
            <h2 className="text-base font-semibold">Adicionar cliente fixo</h2>
            <p className="text-xs text-muted-foreground">Crie uma reserva recorrente semanal.</p>
          </div>
          <Button type="button" variant={showForm ? "secondary" : "outline"} className="w-full" onClick={() => setShowForm(value => !value)}>
            <Plus className="h-4 w-4" />{showForm ? "Fechar cadastro" : "Novo cliente fixo"}
          </Button>
        </div>
        {showForm && (
          <form className="mt-5 space-y-4 border-t border-border pt-5" onSubmit={async event => {
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
              setShowForm(false);
              await loadFixedClients();
              onSaved();
            } catch { toast.error("Não foi possível reservar. Tente novamente."); }
            finally { setBusy(false); }
          }}>
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
          </form>
        )}
      </section>
    </div>
  );
}
