import { useEffect, useMemo, useState } from "react";
import { Lock, Unlock } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { addDaysISO, buildSlots, isHolidayBlockedDate, todayISO, weekdayOfISO, type ScheduleDay, type Taken } from "@/lib/booking";

type Block = Taken & { id: string };

export function ScheduleBlocks({ barberId, days }: { barberId: string; days: ScheduleDay[] }) {
  const [date, setDate] = useState(todayISO());
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [taken, setTaken] = useState<Taken[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const day = days.find((d) => d.weekday === weekdayOfISO(date));

  const allTimes = useMemo(() => {
    if (!day) return [] as string[];
    return Array.from(new Set([...buildSlots(day), ...blocks.map((b) => b.booking_time)])).sort();
  }, [day, blocks]);

  function toMinutes(value: string) {
    const [h = 0, m = 0] = value.split(":").map(Number);
    return h * 60 + m;
  }

  useEffect(() => {
    let active = true;
    setLoading(true);
    async function load() {
      if (!barberId) { if (active) setLoading(false); return; }
      const [blocked, booked] = await Promise.all([
        supabase.from("schedule_blocks").select("id, booking_time, duration_min").eq("barber_id", barberId).eq("booking_date", date),
        supabase.from("bookings").select("booking_time, duration_min").eq("barber_id", barberId).eq("booking_date", date).neq("status", "cancelado"),
      ]);
      if (!active) return;
      setFailed(!!blocked.error || !!booked.error);
      setBlocks(blocked.data ?? []);
      setTaken(booked.data ?? []);
      setLoading(false);
    }
    void load();
    const channel = supabase.channel(`blocks-admin-${barberId}-${date}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "schedule_blocks" }, () => void load())
      .on("postgres_changes", { event: "*", schema: "public", table: "bookings" }, () => void load())
      .subscribe();
    return () => { active = false; void supabase.removeChannel(channel); };
  }, [barberId, date]);

  async function toggle(time: string) {
    if (!barberId || !day || saving) return;
    setSaving(time);
    const block = blocks.find((b) => b.booking_time === time);
    if (block) {
      const { error } = await supabase.from("schedule_blocks").delete().eq("id", block.id);
      if (error) toast.error("Não foi possível liberar o horário.");
      else setBlocks((prev) => prev.filter((b) => b.id !== block.id));
    } else {
      const { data, error } = await supabase.from("schedule_blocks").insert({ barber_id: barberId, booking_date: date, booking_time: time, duration_min: day.slot_min }).select("id, booking_time, duration_min").single();
      if (error) toast.error(error.code === "23505" ? "Horário já ocupado. Atualize os horários." : "Não foi possível bloquear o horário.");
      else if (data) setBlocks((prev) => [...prev, data]);
    }
    setSaving(null);
  }

  return <section className="space-y-3">
    <h2 className="text-base font-semibold">Bloquear horários</h2>
    <p className="text-xs text-muted-foreground">
      Escolha uma data e toque no horário para bloquear ou liberar. O bloqueio vale só para este barbeiro.
    </p>
    <div className="flex flex-wrap gap-2">
      <select aria-label="Dia para bloquear horários" value={date} onChange={(e) => setDate(e.target.value)} className="min-w-0 flex-1 rounded-lg border border-border bg-card px-3 py-2 text-sm">
        {Array.from(new Set([date, ...Array.from({ length: 30 }, (_, i) => addDaysISO(todayISO(), i))])).sort().map((d) => <option key={d} value={d}>{new Date(`${d}T12:00:00`).toLocaleDateString("pt-BR", { weekday: "long", day: "numeric", month: "short" })}</option>)}
      </select>
      <input type="date" aria-label="Outra data para bloquear" min={todayISO()} value={date} onChange={(e) => { if (e.target.value && !isHolidayBlockedDate(e.target.value)) setDate(e.target.value); }} className="min-w-0 rounded-lg border border-border bg-card px-3 py-2 text-sm" />
    </div>
    {!barberId ? <p className="text-sm text-muted-foreground">Selecione um barbeiro.</p> : loading ? <p className="text-sm text-muted-foreground">Carregando horários…</p> : failed ? <p className="text-sm text-destructive">Não foi possível carregar os horários.</p> : !day?.is_open ? <p className="text-sm text-muted-foreground">Fechado neste dia.</p> : <div className="grid grid-cols-3 gap-2">
      {allTimes.map((time) => {
        const block = blocks.find((b) => b.booking_time === time);
        const start = toMinutes(time);
        const occupied = taken.some((b) => toMinutes(b.booking_time) < start + day.slot_min && toMinutes(b.booking_time) + b.duration_min > start);
        return <Button key={time} variant={block ? "destructive" : "outline"} disabled={!!saving || occupied} aria-label={`${block ? "Liberar" : occupied ? "Agendado" : "Bloquear"} ${time}`} aria-pressed={!!block} onClick={() => void toggle(time)} className="h-14 flex-col gap-0.5 px-1">
          <span className="flex items-center gap-1">{block ? <Lock className="h-3 w-3" /> : <Unlock className="h-3 w-3" />}{time}</span>
          <span className="text-[10px]">{saving === time ? "Salvando…" : block ? "Bloqueado" : occupied ? "Agendado" : "Livre"}</span>
        </Button>;
      })}
    </div>}
  </section>;
}
