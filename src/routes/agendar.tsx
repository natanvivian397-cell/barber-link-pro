import { useEffect, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Calendar, CheckCircle2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/BrandHeader";
import { Button } from "@/components/ui/button";
import { CatalogPhoto } from "@/components/CatalogPhoto";
import logo from "@/assets/bom-jesus-logo.png.asset.json";
import {
  addDaysISO,
  availableSlots,
  buildSlots,
  formatBRL,
  formatDateBR,
  isBookableDate,
  isHolidayBlockedDate,
  todayISO,
  weekdayOfISO,
  type ScheduleDay,
  type Barber,
  type Service,
  type Taken,
} from "@/lib/booking";

type SearchParams = { servico: string | undefined };

function slotOverlapsBooking(slot: string, duration: number, bookings: Taken[]) {
  const [hour = 0, minute = 0] = slot.split(":").map(Number);
  const start = hour * 60 + minute;
  return bookings.some((booking) => {
    const [bookingHour = 0, bookingMinute = 0] = booking.booking_time.split(":").map(Number);
    const bookingStart = bookingHour * 60 + bookingMinute;
    return bookingStart < start + duration && bookingStart + (booking.duration_min || 30) > start;
  });
}

export const Route = createFileRoute("/agendar")({
  validateSearch: (search: Record<string, unknown>): SearchParams => ({
    servico: typeof search['servico'] === "string" ? (search['servico'] as string) : undefined,
  }),

  head: () => ({
    meta: [
      { title: "Agendar horário — Barbearia Bom Jesus" },
      {
        name: "description",
        content: "Escolha serviço, dia e horário e confirme seu agendamento na Barbearia Bom Jesus.",
      },
      { property: "og:title", content: "Agendar horário — Barbearia Bom Jesus" },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
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
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authMode, setAuthMode] = useState<"signup" | "login">("signup");
  const [authenticatedEmail, setAuthenticatedEmail] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<null | { time: string; date: string; service: string }>(null);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (mounted) setAuthenticatedEmail(data.session?.user.email ?? null);
    });
    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      setAuthenticatedEmail(session?.user.email ?? null);
    });
    return () => {
      mounted = false;
      authListener.subscription.unsubscribe();
    };
  }, []);

  const { data: services, refetch: refetchServices } = useQuery({
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

  useEffect(() => {
    const channel = supabase
      .channel("services-live-agendar")
      .on("postgres_changes", { event: "*", schema: "public", table: "services" }, () => {
        refetchServices();
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [refetchServices]);

  const { data: barbers, refetch: refetchBarbers } = useQuery({
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

  useEffect(() => {
    const channel = supabase.channel("barbers-live-agendar")
      .on("postgres_changes", { event: "*", schema: "public", table: "barbers" }, () => { refetchBarbers(); })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [refetchBarbers]);

  const { data: taken, refetch: refetchTaken } = useQuery({
    queryKey: ["taken", date, barberId],
    enabled: !!barberId,
    refetchInterval: 15000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("get_public_booking_slots", {
        _barber_id: barberId!,
        _booking_date: date,
      });
      if (error) throw error;
      return (data ?? []) as Taken[];
    },
  });

  const { data: blocked, refetch: refetchBlocked, isSuccess: blocksReady } = useQuery({
    queryKey: ["schedule-blocks", date, barberId],
    enabled: !!barberId,
    queryFn: async () => {
      const { data, error } = await supabase.from("schedule_blocks").select("booking_time, duration_min").eq("booking_date", date).eq("barber_id", barberId ?? "");
      if (error) throw error;
      return data ?? [];
    },
  });

  useEffect(() => {
    const channel = supabase.channel("blocks-live-agendar")
      .on("postgres_changes", { event: "*", schema: "public", table: "schedule_blocks" }, () => { void refetchBlocked(); })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [refetchBlocked]);

  const { data: schedule, refetch: refetchSchedule } = useQuery({
    queryKey: ["schedule", barberId],
    enabled: !!barberId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("schedule_settings")
        .select("*")
        .eq("barber_id", barberId ?? "");
      if (error) throw error;
      return (data ?? []) as ScheduleDay[];
    },
  });

  useEffect(() => {
    const channel = supabase
      .channel(`schedule-live-public-${barberId ?? "none"}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "schedule_settings" },
        () => {
          void refetchSchedule();
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [refetchSchedule]);

  const day = schedule?.find((d) => d.weekday === weekdayOfISO(date));
  const selectedService = services?.find((s) => s.id === serviceId);
  const isClosedDay = isHolidayBlockedDate(date) || day?.is_open === false;
  const slots = barberId
    ? isClosedDay
      ? []
      : blocksReady ? availableSlots(day, selectedService?.duration_min ?? 30, [...(taken ?? []), ...(blocked ?? [])], date) : []
    : isClosedDay ? [] : buildSlots(day);
  const candidateSlots = barberId && blocksReady && taken !== undefined
    ? availableSlots(day, selectedService?.duration_min ?? 30, [], date)
    : [];
  const visibleSlots = candidateSlots.filter((slot) =>
    slots.includes(slot) || slotOverlapsBooking(slot, selectedService?.duration_min ?? 30, taken ?? []),
  );
  const days = Array.from({ length: 30 }, (_, i) => addDaysISO(todayISO(), i));

  useEffect(() => {
    if (time && barberId && !slots.includes(time)) setTime(null);
  }, [slots.join(","), time, barberId]);

  useEffect(() => {
    if (barberId && barbers && !barbers.some((b) => b.id === barberId)) {
      setBarberId(undefined);
      setTime(null);
    }
  }, [barberId, barbers]);

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
    if (isHolidayBlockedDate(date) || !isBookableDate(date, schedule)) {
      toast.error("Esta data não está disponível para agendamento.");
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

    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData.session) {
      if (!email.trim() || !/^\S+@\S+\.\S+$/.test(email.trim())) {
        setSaving(false);
        toast.error("Informe um e-mail válido para proteger seus agendamentos.");
        return;
      }
      if (password.length < 8) {
        setSaving(false);
        toast.error("Sua senha deve ter pelo menos 8 caracteres.");
        return;
      }

      if (authMode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email: email.trim().toLowerCase(),
          password,
          options: { data: { full_name: name.trim(), phone: phone.trim() } },
        });
        if (error) {
          setSaving(false);
          const code = (error as { code?: string }).code ?? "";
          const msg = error.message.toLowerCase();
          toast.error(
            code === "weak_password" || msg.includes("weak")
              ? "Essa senha é muito comum e fácil de adivinhar. Crie uma senha diferente, misturando letras e números."
              : code === "user_already_exists" || msg.includes("already registered")
                ? "Este e-mail já possui uma conta. Selecione Já tenho conta."
                : code === "email_address_invalid" || msg.includes("invalid")
                  ? "Este e-mail não é válido. Confira e tente novamente."
                  : code.includes("rate_limit") || error.status === 429
                    ? "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente de novo."
                    : "Não foi possível criar sua conta. Confira os dados e tente novamente.",
          );
          return;
        }
        if (!data.session) {
          setSaving(false);
          toast.info("Conta criada. Confirme seu e-mail pelo link enviado e depois entre para concluir o agendamento.");
          setAuthMode("login");
          return;
        }
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email: email.trim().toLowerCase(),
          password,
        });
        if (error || !data.session) {
          setSaving(false);
          toast.error("E-mail ou senha inválidos. Tente novamente.");
          return;
        }
      }
    }

    const { error } = await supabase.rpc("create_booking_authenticated", {
      _barber_id: barberId,
      _customer_name: name.trim(),
      _customer_phone: phone.trim(),
      _service_id: selected.id,
      _booking_date: date,
      _booking_time: time,
      ...(notes.trim() ? { _notes: notes.trim() } : {}),
    });
    setSaving(false);

    if (error) {
      if (error.code === "23505") {
        toast.error("Esse horário acabou de ser reservado. Escolha outro.");
        setTime(null);
        refetchTaken();
        return;
      }
      toast.error(error.message.includes("horário") ? error.message : "Não foi possível agendar. Tente novamente.");
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
            to="/meus-agendamentos"
            className="mt-8 rounded-full bg-gold px-7 py-3.5 text-sm font-semibold text-gold-foreground"
          >
            Consultar meus agendamentos
          </Link>
          <a
            href="/agendar"
            className="mt-3 rounded-full border border-border px-7 py-3.5 text-sm font-semibold text-foreground"
          >
            Voltar ao início
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pb-12">
      <main className="mx-auto max-w-2xl px-5 sm:px-8">
        <div className="pt-10 text-center sm:pt-14">
          <Link to="/" className="inline-block" aria-label="Barbearia Bom Jesus — início">
            <img src={logo.url} alt="Barbearia Bom Jesus" className="mx-auto h-40 w-40 object-contain sm:h-48 sm:w-48" />
          </Link>
          <h1 className="mt-4 font-display text-xl font-semibold uppercase tracking-[0.28em] text-gold sm:text-2xl">Barbearia Bom Jesus</h1>
          <p className="mt-3 text-xs uppercase tracking-[0.34em] text-foreground">Corte <span className="px-2 text-gold">•</span> Barba <span className="px-2 text-gold">•</span> Estilo</p>
        </div>

        <section className="mt-12">
          <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">1. &nbsp; Selecione a data</h2>
          {isHolidayBlockedDate(date) ? <p className="mt-3 rounded-xl border border-border bg-card px-4 py-3 text-xs text-muted-foreground">
            Pausa de fim de ano: sem atendimento em 24, 25, 26 e 31 de dezembro e 1º e 2 de janeiro.
          </p> : null}
          <label className="mt-4 flex items-center rounded-full border border-border bg-card px-5 py-3 text-foreground focus-within:border-gold">
            <Calendar className="mr-3 h-5 w-5 shrink-0 text-gold" aria-hidden="true" />
            <select aria-label="Selecionar data" value={date} onChange={(e) => { setDate(e.target.value); setTime(null); }} className="min-w-0 flex-1 cursor-pointer bg-transparent text-sm outline-none">
              {days.map((d) => {
                const openDay = schedule?.find((s) => s.weekday === weekdayOfISO(d));
                const isHoliday = isHolidayBlockedDate(d);
                const disabled = isHoliday || openDay?.is_open === false;
                return <option key={d} value={d} disabled={disabled} className="bg-card text-foreground">{new Date(`${d}T12:00:00`).toLocaleDateString("pt-BR", { weekday: "long", day: "numeric", month: "short", year: "numeric" })}{isHoliday ? " — recesso" : ""}</option>;
              })}
            </select>
          </label>
        </section>

        <section className="mt-9">
          <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">2. &nbsp; Escolha o barbeiro</h2>
          <div className="mt-4 flex flex-wrap gap-2">
            {barbers?.map((b) => <Button key={b.id} type="button" variant="outline" onClick={() => { setBarberId(b.id); setTime(null); }} className={`h-auto gap-2 rounded-full border px-3 py-2 ${barberId === b.id ? "border-gold bg-gold/10 text-gold" : "border-border bg-card text-foreground"}`}>
              {b.photo_path ? <CatalogPhoto path={b.photo_path} alt={b.name} className="h-11 w-11 rounded-full object-cover" /> : null}{b.name}
            </Button>)}
          </div>
        </section>

        <section className="mt-9">
          <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">3. &nbsp; Escolha o horário</h2>
          {!barberId ? <p className="mt-4 text-sm text-muted-foreground">Escolha o barbeiro para ver os horários livres.</p> : visibleSlots.length === 0 ? <p className="mt-4 text-sm text-muted-foreground">{day?.is_open === false ? "A barbearia não atende nesse dia. Escolha outra data." : "Sem horários disponíveis nesse dia. Escolha outra data."}</p> : null}
          <div className="mt-4 grid grid-cols-3 gap-2.5">
            {visibleSlots.map((slot) => {
              const occupied = slotOverlapsBooking(slot, selectedService?.duration_min ?? 30, taken ?? []);
              return <Button key={slot} type="button" variant="outline" disabled={occupied} onClick={() => setTime(slot)} aria-label={occupied ? `${slot}, horário ocupado` : slot} className={`h-12 rounded-full border text-sm font-medium ${occupied ? "cursor-not-allowed border-border bg-muted text-muted-foreground line-through opacity-60" : time === slot ? "border-gold bg-gold/10 text-gold" : "border-border bg-card text-foreground"}`}>{slot}</Button>;
            })}
          </div>
        </section>

        <section className="mt-11">
          <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">4. &nbsp; Selecione o serviço</h2>
          <div className="mt-4 space-y-2">
            {services?.map((s) => <Button key={s.id} type="button" variant="outline" onClick={() => setServiceId(s.id)} className={`h-auto min-h-14 w-full justify-start gap-3 rounded-full border px-4 py-2 text-left font-normal ${serviceId === s.id ? "border-gold bg-gold/10 text-gold" : "border-border bg-card text-foreground"}`}>
              {s.photo_path ? <CatalogPhoto path={s.photo_path} alt={s.name} className="h-12 w-12 shrink-0 rounded-full object-cover" /> : null}
              <span className="min-w-0 flex-1 whitespace-normal break-normal leading-snug">{s.name.replace(/\+/g, " + ")} <span className="text-xs text-muted-foreground">· {s.duration_min} min</span></span>
              <span className="shrink-0">R$ {formatBRL(s.price)}</span>
              <span aria-hidden="true" className={`ml-1 h-5 w-5 shrink-0 rounded-full border ${serviceId === s.id ? "border-gold bg-gold" : "border-muted-foreground"}`} />
            </Button>)}
          </div>
        </section>

        <section className="mt-11 space-y-3">
          <h2 className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">5. &nbsp; Seus dados</h2>
          <input aria-label="Seu nome" value={name} onChange={(e) => setName(e.target.value)} placeholder="Seu nome" className="w-full rounded-full border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-gold" />
          <input aria-label="WhatsApp" value={phone} onChange={(e) => {
            const d = e.target.value.replace(/\D/g, "").slice(0, 11);
            setPhone(d.length <= 2 ? (d ? `(${d}` : "") : d.length <= 7 ? `(${d.slice(0, 2)}) ${d.slice(2)}` : `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`);
          }} inputMode="tel" placeholder="WhatsApp (51) 99999-9999" className="w-full rounded-full border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-gold" />
          {authenticatedEmail ? (
            <p className="rounded-2xl border border-gold/30 bg-gold/5 px-4 py-3 text-sm text-foreground">
              Conta conectada: <strong>{authenticatedEmail}</strong>
            </p>
          ) : (
            <div className="space-y-3 rounded-2xl border border-border bg-card p-4">
              <div>
                <p className="text-sm font-semibold text-foreground">Proteja seus agendamentos</p>
                <p className="mt-1 text-xs text-muted-foreground">Crie uma conta rápida ou entre para consultar e cancelar suas reservas com segurança.</p>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <button type="button" onClick={() => setAuthMode("signup")} className={`rounded-full px-3 py-2 text-xs font-semibold ${authMode === "signup" ? "bg-gold text-gold-foreground" : "border border-border text-muted-foreground"}`}>Criar conta</button>
                <button type="button" onClick={() => setAuthMode("login")} className={`rounded-full px-3 py-2 text-xs font-semibold ${authMode === "login" ? "bg-gold text-gold-foreground" : "border border-border text-muted-foreground"}`}>Já tenho conta</button>
              </div>
              <input aria-label="E-mail" type="email" autoComplete="email" value={email} onChange={(e) => {
                const v = e.target.value.replace(/\s/g, "");
                setEmail(v.endsWith("@") && !email.includes("@") && v.length > email.length ? `${v}gmail.com` : v);
              }} onBlur={() => { if (email && !email.includes("@")) setEmail(`${email}@gmail.com`); }} placeholder="Seu e-mail" className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm outline-none focus:border-gold" />
              <input aria-label="Senha" type="password" autoComplete={authMode === "signup" ? "new-password" : "current-password"} value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Senha (mínimo 8 caracteres)" className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm outline-none focus:border-gold" />
            </div>
          )}
          <textarea aria-label="Observação" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Observação (opcional)" rows={2} className="w-full resize-none rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-gold" />
        </section>
        <Button type="button" onClick={submit} disabled={saving} className="mt-7 h-14 w-full gap-3 rounded-full bg-gold text-sm font-semibold uppercase tracking-[0.15em] text-gold-foreground hover:bg-gold/90">
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : null} Confirmar agendamento <ArrowRight className="h-4 w-4" />
        </Button>
        <Link
          to="/meus-agendamentos"
          className="mt-6 flex w-full items-center justify-center gap-2 rounded-full border border-gold px-5 py-3.5 text-sm font-semibold text-gold transition-colors hover:bg-gold/10"
        >
          <Calendar className="h-4 w-4" /> Meus agendamentos
        </Link>
        <p className="mt-8 text-center text-xs uppercase tracking-[0.3em] text-gold">— &nbsp; Desde 2015 &nbsp; —</p>
      </main>
    </div>
  );
}
