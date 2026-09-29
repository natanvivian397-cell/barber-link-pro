import { useEffect, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/BrandHeader";
import {
  buildSlots,
  formatBRL,
  formatDateBR,
  todayISO,
  weekdayOfISO,
  type ScheduleDay,
  type Barber,
  type Service,
} from "@/lib/booking";

type SearchParams = { servico: string | undefined };

export const Route = createFileRoute("/agendar")({
  validateSearch: (search: Record<string, unknown>): SearchParams => ({
    servico: typeof search['servico'] === "string" ? (search['servico'] as string) : undefined,
  }),

  head: () => ({
    meta: [
      { title: "Agendar horário — The Brother's Barber" },
      {
        name: "description",
        content: "Escolha serviço, dia e horário e confirme seu agendamento na The Brother's Barber.",
      },
      { property: "og:title", content: "Agendar horário — The Brother's Barber" },
      {
        property: "og:description",
        content: "Escolha serviço, dia e horário e confirme seu agendamento.",
      },
    ],
  }),
  component: Agendar,
});

function Agendar() {
  const { servico } = Route.useSearch();
  const [serviceId, setServiceId] = useState<string | undefined>(servico);
  const [barberId, setBarberId] = useState<string | undefined>(undefined);
  const [date, setDate] = useState(todayISO());
  const [time, setTime] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<null | { time: string; date: string; service: string }>(null);

  const { data: services } = useQuery({
    queryKey: ["services"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("services")
        .select("*")
        .eq("active", true)
        .order("sort_order");
      if (error) throw error;
      return data as Service[];
    },
  });

  const { data: barbers } = useQuery({
    queryKey: ["barbers"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("barbers")
        .select("*")
        .eq("active", true)
        .order("sort_order");
      if (error) throw error;
      return data as Barber[];
    },
  });

  const { data: taken, refetch: refetchTaken } = useQuery({
    queryKey: ["taken", date, barberId],
    enabled: !!barberId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bookings")
        .select("booking_time, status")
        .eq("booking_date", date)
        .eq("barber_id", barberId!);
      if (error) throw error;
      return (data ?? [])
        .filter((b) => b.status !== "cancelado")
        .map((b) => b.booking_time as string);
    },
  });

  const { data: schedule, refetch: refetchSchedule } = useQuery({
    queryKey: ["schedule"],
    queryFn: async () => {
      const { data, error } = await supabase.from("schedule_settings").select("*");
      if (error) throw error;
      return (data ?? []) as ScheduleDay[];
    },
  });

  useEffect(() => {
    const channel = supabase
      .channel("schedule-live-public")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "schedule_settings" },
        () => {
          refetchSchedule();
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [refetchSchedule]);

  const day = schedule?.find((d) => d.weekday === weekdayOfISO(date));
  const slots = buildSlots(day);

  const selected = services?.find((s) => s.id === serviceId);

  async function submit() {
    if (!selected) {
      toast.error("Escolha um serviço.");
      return;
    }
    if (!time) {
      toast.error("Escolha um horário.");
      return;
    }
    if (name.trim().length < 2) {
      toast.error("Informe seu nome.");
      return;
    }
    if (phone.replace(/\D/g, "").length < 10) {
      toast.error("Informe um WhatsApp válido.");
      return;
    }
    if (!barberId) {
      toast.error("Escolha o barbeiro.");
      return;
    }

    setSaving(true);
    const { error } = await supabase.from("bookings").insert({
      barber_id: barberId,
      customer_name: name.trim(),
      customer_phone: phone.trim(),
      service_id: selected.id,
      service_name: selected.name,
      price: selected.price,
      booking_date: date,
      booking_time: time,
      notes: notes.trim() || null,
    });
    setSaving(false);

    if (error) {
      if (error.code === "23505") {
        toast.error("Esse horário acabou de ser reservado. Escolha outro.");
        setTime(null);
        refetchTaken();
        return;
      }
      toast.error("Não foi possível agendar. Tente novamente.");
      return;
    }
    setDone({ time, date, service: selected.name });
  }

  if (done) {
    return (
      <div className="min-h-screen">
        <BrandHeader back />
        <div className="flex flex-col items-center px-6 pt-16 text-center">
          <CheckCircle2 className="h-14 w-14 text-success" />
          <h1 className="mt-5 text-3xl font-bold">Agendamento confirmado!</h1>
          <p className="mt-3 text-muted-foreground">
            {done.service}
            <br />
            {formatDateBR(done.date)} às {done.time}
          </p>
          <p className="mt-2 text-sm text-muted-foreground">
            Já avisamos a barbearia. Te esperamos!
          </p>
          <Link
            to="/"
            className="mt-8 rounded-full bg-primary px-7 py-3.5 text-sm font-semibold text-primary-foreground"
          >
            Voltar ao início
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen pb-32">
      <BrandHeader back />

      <div className="px-6 pt-4">
        <p className="eyebrow">Novo agendamento</p>
        <h1 className="mt-2 text-3xl font-bold">Escolha seu horário</h1>
      </div>

      <section className="px-6 pt-8">
        <p className="eyebrow">1. Serviço</p>
        <div className="mt-3 space-y-2">
          {services?.map((s) => {
            const active = s.id === serviceId;
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => setServiceId(s.id)}
                className={`flex w-full items-center justify-between gap-3 rounded-2xl border px-5 py-3.5 text-left transition-colors ${
                  active
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-border bg-card text-foreground"
                }`}
              >
                <span className="truncate text-sm font-semibold">{s.name}</span>
                <span className="shrink-0 text-sm font-bold">R$ {formatBRL(s.price)}</span>
              </button>
            );
          })}
        </div>
      </section>

      <section className="px-6 pt-8">
        <p className="eyebrow">Barbeiro</p>
        <div className="mt-3 flex flex-wrap gap-2">
          {barbers?.map((b) => (
            <button
              key={b.id}
              type="button"
              onClick={() => {
                setBarberId(b.id);
                setTime(null);
              }}
              className={`rounded-full border px-5 py-2.5 text-sm font-semibold transition-colors ${
                barberId === b.id
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border bg-card text-foreground"
              }`}
            >
              {b.name}
            </button>
          ))}
        </div>
      </section>

      <section className="px-6 pt-8">
        <p className="eyebrow">2. Data</p>
        <input
          type="date"
          value={date}
          min={todayISO()}
          onChange={(e) => {
            setDate(e.target.value);
            setTime(null);
          }}
          className="mt-3 w-full rounded-2xl border border-border bg-card px-5 py-3.5 text-sm font-semibold text-foreground outline-none focus:border-primary"
        />
      </section>

      <section className="px-6 pt-8">
        <p className="eyebrow">3. Horário</p>
        {slots.length === 0 ? (
          <p className="mt-3 rounded-2xl border border-border bg-muted px-5 py-4 text-sm text-muted-foreground">
            A barbearia não atende nesse dia. Escolha outra data.
          </p>
        ) : null}
        <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-5">
          {slots.map((slot) => {
            const busy = taken?.includes(slot);
            const active = time === slot;
            return (
              <button
                key={slot}
                type="button"
                disabled={busy}
                onClick={() => setTime(slot)}
                className={`rounded-xl border px-2 py-3 text-sm font-semibold transition-colors ${
                  busy
                    ? "cursor-not-allowed border-border bg-muted text-muted-foreground line-through"
                    : active
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-card text-foreground"
                }`}
              >
                {slot}
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-3 px-6 pt-8">
        <p className="eyebrow">4. Seus dados</p>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Seu nome"
          className="w-full rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-primary"
        />
        <input
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          inputMode="tel"
          placeholder="WhatsApp (51) 9 9999-9999"
          className="w-full rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-primary"
        />
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="Observação (opcional)"
          rows={3}
          className="w-full resize-none rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-primary"
        />
      </section>

      <div className="fixed inset-x-0 bottom-0 bg-gradient-to-t from-background via-background to-transparent px-6 pb-6 pt-8">
        <button
          type="button"
          onClick={submit}
          disabled={saving}
          className="mx-auto flex w-full max-w-xl items-center justify-center gap-2 rounded-full bg-primary px-7 py-4 text-sm font-semibold tracking-[0.12em] text-primary-foreground shadow-float disabled:opacity-60"
        >
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
          CONFIRMAR AGENDAMENTO
        </button>
      </div>
    </div>
  );
}
