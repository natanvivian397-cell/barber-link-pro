import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import type { Session } from "@supabase/supabase-js";
import { Check, CheckCheck, Clock, Download, LogOut, Loader2, Phone, Plus, Share, X } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/BrandHeader";
import {
  WEEKDAY_NAMES,
  formatBRL,
  formatDateBR,
  todayISO,
  type Barber,
  type Booking,
  type ScheduleDay,
} from "@/lib/booking";

export const Route = createFileRoute("/admin")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Painel — The Brother's Barber" },
      { name: "description", content: "Painel da barbearia com os agendamentos em tempo real." },
      { name: "robots", content: "noindex" },
      { name: "theme-color", content: "#121214" },
      { name: "apple-mobile-web-app-capable", content: "yes" },
      { name: "apple-mobile-web-app-title", content: "Painel Barber" },
      { property: "og:title", content: "Painel — The Brother's Barber" },
      { property: "og:description", content: "Agendamentos em tempo real da barbearia." },
    ],
    links: [
      { rel: "manifest", href: "/manifest.webmanifest" },
      { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
    ],
  }),
  component: Admin,
});

function InstallApp() {
  const [prompt, setPrompt] = useState<any>(null);
  const [installed, setInstalled] = useState(false);
  const [showIos, setShowIos] = useState(false);

  useEffect(() => {
    const onPrompt = (e: Event) => {
      e.preventDefault();
      setPrompt(e);
    };
    window.addEventListener("beforeinstallprompt", onPrompt);
    window.addEventListener("appinstalled", () => setInstalled(true));

    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      (window.navigator as any).standalone === true;
    if (standalone) setInstalled(true);

    const isPreview =
      window.top !== window.self ||
      window.location.hostname === "localhost" ||
      window.location.hostname.includes("id-preview");
    if (!isPreview && "serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  if (installed) return null;

  const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);

  return (
    <div className="px-6 pt-6">
      <button
        type="button"
        onClick={async () => {
          if (prompt) {
            prompt.prompt();
            await prompt.userChoice;
            setPrompt(null);
            return;
          }
          setShowIos((v) => !v);
        }}
        className="flex w-full items-center justify-center gap-2 rounded-2xl border border-border bg-card px-5 py-3.5 text-sm font-semibold"
      >
        <Download className="h-4 w-4" /> Instalar o painel no celular
      </button>
      {showIos && !prompt ? (
        <p className="mt-2 flex items-start gap-2 rounded-2xl bg-muted px-4 py-3 text-xs text-muted-foreground">
          <Share className="mt-0.5 h-4 w-4 shrink-0" />
          {isIos
            ? "No iPhone: toque em Compartilhar no Safari e escolha “Adicionar à Tela de Início”."
            : "No navegador do celular: abra o menu (⋮) e escolha “Instalar app” ou “Adicionar à tela inicial”."}
        </p>
      ) : null}
    </div>
  );
}

function ScheduleEditor() {
  const [days, setDays] = useState<ScheduleDay[]>([]);
  const [saving, setSaving] = useState<number | null>(null);

  async function load() {
    const { data } = await supabase.from("schedule_settings").select("*").order("weekday");
    setDays((data ?? []) as ScheduleDay[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function save(day: ScheduleDay, patch: Partial<ScheduleDay>) {
    const next = { ...day, ...patch };
    setDays((prev) => prev.map((d) => (d.weekday === day.weekday ? next : d)));
    setSaving(day.weekday);
    const { error } = await supabase
      .from("schedule_settings")
      .update({
        is_open: next.is_open,
        morning_start: next.morning_start,
        morning_end: next.morning_end,
        afternoon_start: next.afternoon_start,
        afternoon_end: next.afternoon_end,
        slot_min: next.slot_min,
      })
      .eq("weekday", day.weekday);
    setSaving(null);
    if (error) {
      toast.error("Não foi possível salvar.");
      load();
    }
  }

  return (
    <div className="space-y-3 px-6 pt-6">
      <p className="text-sm text-muted-foreground">
        Desligue os dias em que não trabalha e ajuste os horários. Vale na hora para quem agenda.
      </p>
      {days.map((d) => (
        <div key={d.weekday} className="rounded-2xl border border-border bg-card p-4 shadow-card">
          <div className="flex items-center justify-between">
            <p className="text-base font-semibold">{WEEKDAY_NAMES[d.weekday]}</p>
            <button
              type="button"
              onClick={() => save(d, { is_open: !d.is_open })}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
                d.is_open
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              }`}
            >
              {saving === d.weekday ? "..." : d.is_open ? "Aberto" : "Fechado"}
            </button>
          </div>

          {d.is_open ? (
            <div className="mt-3 space-y-2">
              <div className="flex items-center gap-2">
                <span className="w-16 text-xs text-muted-foreground">Manhã</span>
                <input
                  type="time"
                  value={d.morning_start}
                  onChange={(e) => save(d, { morning_start: e.target.value })}
                  className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
                />
                <input
                  type="time"
                  value={d.morning_end}
                  onChange={(e) => save(d, { morning_end: e.target.value })}
                  className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="w-16 text-xs text-muted-foreground">Tarde</span>
                <input
                  type="time"
                  value={d.afternoon_start}
                  onChange={(e) => save(d, { afternoon_start: e.target.value })}
                  className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
                />
                <input
                  type="time"
                  value={d.afternoon_end}
                  onChange={(e) => save(d, { afternoon_end: e.target.value })}
                  className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="w-16 text-xs text-muted-foreground">Cortes</span>
                <select
                  value={d.slot_min}
                  onChange={(e) => save(d, { slot_min: Number(e.target.value) })}
                  className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
                >
                  {[15, 20, 30, 40, 45, 60].map((m) => (
                    <option key={m} value={m}>
                      a cada {m} min
                    </option>
                  ))}
                </select>
              </div>
            </div>
          ) : null}
        </div>
      ))}
    </div>
  );
}

function Admin() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return session ? <Panel /> : <LoginCard />;
}

function LoginCard() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    if (mode === "login") {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) toast.error("E-mail ou senha inválidos.");
    } else {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { emailRedirectTo: `${window.location.origin}/admin` },
      });
      if (error) toast.error(error.message);
      else if (!data.session) toast.success("Conta criada. Confirme pelo e-mail para entrar.");
    }
    setBusy(false);
  }

  return (
    <div className="min-h-screen">
      <BrandHeader back />
      <div className="mx-auto max-w-sm px-6 pt-12">
        <p className="eyebrow">Área da barbearia</p>
        <h1 className="mt-2 text-3xl font-bold">
          {mode === "login" ? "Entrar no painel" : "Criar acesso"}
        </h1>
        <div className="mt-6 space-y-3">
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            type="email"
            placeholder="E-mail"
            className="w-full rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-primary"
          />
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            placeholder="Senha"
            className="w-full rounded-2xl border border-border bg-card px-5 py-3.5 text-sm outline-none focus:border-primary"
          />
          <button
            type="button"
            onClick={submit}
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-full bg-primary px-7 py-4 text-sm font-semibold tracking-[0.12em] text-primary-foreground disabled:opacity-60"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            {mode === "login" ? "ENTRAR" : "CRIAR CONTA"}
          </button>
          <button
            type="button"
            onClick={() => setMode(mode === "login" ? "signup" : "login")}
            className="w-full text-center text-sm text-muted-foreground underline"
          >
            {mode === "login" ? "Primeiro acesso? Criar conta" : "Já tenho conta"}
          </button>
        </div>
      </div>
    </div>
  );
}

function BarbersEditor({ barbers, reload }: { barbers: Barber[]; reload: () => void }) {
  const [newName, setNewName] = useState("");

  async function add() {
    if (!newName.trim()) return;
    const { error } = await supabase
      .from("barbers")
      .insert({ name: newName.trim(), sort_order: barbers.length + 1 });
    if (error) toast.error("Não foi possível cadastrar.");
    else setNewName("");
    reload();
  }
  async function rename(id: string, name: string) {
    if (!name.trim()) return;
    await supabase.from("barbers").update({ name: name.trim() }).eq("id", id);
    reload();
  }
  async function toggle(b: Barber) {
    await supabase.from("barbers").update({ active: !b.active }).eq("id", b.id);
    reload();
  }

  return (
    <div className="space-y-3 px-6 pt-6">
      <p className="text-sm text-muted-foreground">
        Barbeiros ativos aparecem no site para o cliente escolher.
      </p>
      {barbers.map((b) => (
        <div key={b.id} className="flex items-center gap-2 rounded-2xl border border-border bg-card p-3">
          <input
            defaultValue={b.name}
            onBlur={(e) => e.target.value !== b.name && rename(b.id, e.target.value)}
            className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm"
          />
          <button
            type="button"
            onClick={() => toggle(b)}
            className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
              b.active ? "bg-primary text-primary-foreground" : "border border-border text-muted-foreground"
            }`}
          >
            {b.active ? "Ativo" : "Inativo"}
          </button>
        </div>
      ))}
      <div className="flex gap-2">
        <input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          placeholder="Nome do novo barbeiro"
          className="flex-1 rounded-xl border border-border bg-card px-3 py-2 text-sm"
        />
        <button
          type="button"
          onClick={add}
          className="flex items-center gap-1 rounded-full bg-primary px-4 py-2 text-xs font-semibold text-primary-foreground"
        >
          <Plus className="h-3.5 w-3.5" /> Cadastrar
        </button>
      </div>
    </div>
  );
}

function Panel() {
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [barbers, setBarbers] = useState<Barber[]>([]);
  const [barberId, setBarberId] = useState<string>(() => localStorage.getItem("agenda_barber") ?? "");
  const [filter, setFilter] = useState<"hoje" | "proximos" | "concluidos">("hoje");
  const [tab, setTab] = useState<"agenda" | "horarios" | "barbeiros">("agenda");
  const [loading, setLoading] = useState(true);

  async function load() {
    const { data, error } = await supabase
      .from("bookings")
      .select("*")
      .order("booking_date", { ascending: true })
      .order("booking_time", { ascending: true });
    if (!error) setBookings((data ?? []) as Booking[]);
    setLoading(false);
  }

  async function loadBarbers() {
    const { data } = await supabase.from("barbers").select("*").order("sort_order");
    setBarbers((data ?? []) as Barber[]);
  }

  function pickBarber(id: string) {
    setBarberId(id);
    localStorage.setItem("agenda_barber", id);
  }

  useEffect(() => {
    load();
    loadBarbers();
    const channel = supabase
      .channel("bookings-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "bookings" }, (payload) => {
        if (payload.eventType === "INSERT") {
          const b = payload.new as Booking;
          const mine = localStorage.getItem("agenda_barber");
          if (!mine || b.barber_id === mine)
            toast.success(`Novo agendamento: ${b.customer_name} · ${b.booking_time}`);
        }
        load();
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "barbers" }, () => loadBarbers())
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const today = todayISO();
  const list = useMemo(() => {
    const mine = bookings.filter((b) => b.barber_id === barberId);
    if (filter === "concluidos") return mine.filter((b) => b.status === "concluido");
    const open = mine.filter((b) => b.status !== "concluido");
    if (filter === "hoje") return open.filter((b) => b.booking_date === today);
    return open.filter((b) => b.booking_date >= today);
  }, [bookings, filter, today, barberId]);

  async function setStatus(id: string, status: string) {
    const { error } = await supabase.from("bookings").update({ status }).eq("id", id);
    if (error) toast.error("Não foi possível atualizar.");
  }

  async function transfer(b: Booking, to: string) {
    if (!to) return;
    const { error } = await supabase.from("bookings").update({ barber_id: to }).eq("id", b.id);
    if (error) {
      toast.error(
        error.code === "23505"
          ? "Esse barbeiro já tem cliente nesse horário."
          : "Não foi possível passar o horário.",
      );
      return;
    }
    toast.success(`Passado para ${barbers.find((x) => x.id === to)?.name}`);
  }

  const current = barbers.find((b) => b.id === barberId);

  if (!current && barbers.length > 0 && tab !== "barbeiros") {
    return (
      <div className="min-h-screen px-6 pt-12">
        <p className="eyebrow">Painel</p>
        <h1 className="mt-1 text-2xl font-bold">Qual é a sua agenda?</h1>
        <div className="mt-6 space-y-2">
          {barbers.filter((b) => b.active).map((b) => (
            <button
              key={b.id}
              type="button"
              onClick={() => pickBarber(b.id)}
              className="w-full rounded-2xl border border-border bg-card px-5 py-4 text-left text-base font-semibold"
            >
              {b.name}
            </button>
          ))}
        </div>
        <button
          type="button"
          onClick={() => setTab("barbeiros")}
          className="mt-6 text-sm text-muted-foreground underline"
        >
          Cadastrar barbeiros
        </button>
      </div>
    );
  }

  return (
    <div className="min-h-screen pb-16">
      <header className="flex items-center justify-between px-6 pt-8">
        <div>
          <p className="eyebrow">Agenda de</p>
          <button
            type="button"
            onClick={() => pickBarber("")}
            className="mt-1 text-2xl font-bold underline decoration-border underline-offset-4"
          >
            {current?.name ?? "Agendamentos"}
          </button>
        </div>
        <button
          type="button"
          onClick={() => supabase.auth.signOut()}
          className="flex items-center gap-2 rounded-full border border-border px-4 py-2 text-xs font-medium text-muted-foreground"
        >
          <LogOut className="h-3.5 w-3.5" /> Sair
        </button>
      </header>

      <div className="flex gap-2 px-6 pt-6">
        {(["agenda", "horarios", "barbeiros"] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`flex items-center gap-1.5 rounded-full px-4 py-2 text-xs font-semibold transition-colors ${
              tab === t
                ? "bg-primary text-primary-foreground"
                : "border border-border bg-card text-muted-foreground"
            }`}
          >
            {t === "horarios" ? <Clock className="h-3.5 w-3.5" /> : null}
            {t === "agenda" ? "Agenda" : t === "horarios" ? "Horários" : "Barbeiros"}
          </button>
        ))}
      </div>

      {tab === "horarios" ? <ScheduleEditor /> : null}
      {tab === "horarios" ? <InstallApp /> : null}
      {tab === "barbeiros" ? <BarbersEditor barbers={barbers} reload={loadBarbers} /> : null}

      {tab === "agenda" ? (
        <>
      <div className="flex gap-2 px-6 pt-6">
        {(["hoje", "proximos", "concluidos"] as const).map((f) => (
          <button
            key={f}
            type="button"
            onClick={() => setFilter(f)}
            className={`rounded-full px-4 py-2 text-xs font-semibold capitalize transition-colors ${
              filter === f
                ? "bg-primary text-primary-foreground"
                : "border border-border bg-card text-muted-foreground"
            }`}
          >
            {f === "proximos" ? "próximos" : f === "concluidos" ? "concluídos" : f}
          </button>
        ))}
      </div>

      <div className="space-y-3 px-6 pt-6">
        {loading ? (
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        ) : list.length === 0 ? (
          <p className="pt-10 text-center text-sm text-muted-foreground">
            Nenhum agendamento neste período.
          </p>
        ) : (
          list.map((b) => (
            <div
              key={b.id}
              className="rounded-2xl border border-border bg-card p-5 shadow-card"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-base font-semibold">{b.customer_name}</p>
                  <p className="text-sm text-muted-foreground">{b.service_name}</p>
                </div>
                <div className="text-right">
                  <p className="text-lg font-bold">{b.booking_time}</p>
                  <p className="text-xs text-muted-foreground">{formatDateBR(b.booking_date)}</p>
                </div>
              </div>

              {b.notes ? (
                <p className="mt-3 rounded-xl bg-muted px-3 py-2 text-xs text-muted-foreground">
                  {b.notes}
                </p>
              ) : null}

              <div className="mt-4 flex flex-wrap items-center gap-2">
                <span
                  className={`rounded-full px-3 py-1 text-[11px] font-semibold capitalize ${
                    b.status === "confirmado" || b.status === "concluido"
                      ? "bg-success text-success-foreground"
                      : b.status === "cancelado"
                        ? "bg-destructive text-destructive-foreground"
                        : "bg-warning text-warning-foreground"
                  }`}
                >
                  {b.status}
                </span>
                <span className="text-sm font-semibold">R$ {formatBRL(b.price)}</span>
                <a
                  href={`https://wa.me/55${b.customer_phone.replace(/\D/g, "")}`}
                  target="_blank"
                  rel="noreferrer"
                  className="ml-auto flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-xs font-medium"
                >
                  <Phone className="h-3.5 w-3.5" /> WhatsApp
                </a>
                {b.status === "concluido" ? (
                  <button
                    type="button"
                    onClick={() => setStatus(b.id, "confirmado")}
                    className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-muted-foreground"
                  >
                    Reabrir
                  </button>
                ) : (
                  <>
                    <button
                      type="button"
                      onClick={() => setStatus(b.id, "confirmado")}
                      className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-xs font-medium"
                    >
                      <Check className="h-3.5 w-3.5" /> Confirmar
                    </button>
                    <button
                      type="button"
                      onClick={() => setStatus(b.id, "concluido")}
                      className="flex items-center gap-1.5 rounded-full bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground"
                    >
                      <CheckCheck className="h-3.5 w-3.5" /> Finalizar
                    </button>
                    <button
                      type="button"
                      onClick={() => setStatus(b.id, "cancelado")}
                      className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-muted-foreground"
                    >
                      <X className="h-3.5 w-3.5" /> Cancelar
                    </button>
                    <select
                      value=""
                      onChange={(e) => transfer(b, e.target.value)}
                      className="rounded-full border border-border bg-card px-3 py-1.5 text-xs font-medium"
                    >
                      <option value="">Passar para…</option>
                      {barbers
                        .filter((x) => x.active && x.id !== barberId)
                        .map((x) => (
                          <option key={x.id} value={x.id}>
                            {x.name}
                          </option>
                        ))}
                    </select>
                  </>
                )}
              </div>
            </div>
          ))
        )}
      </div>
        </>
      ) : null}
    </div>
  );
}
