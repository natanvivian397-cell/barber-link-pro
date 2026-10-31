import { useEffect, useState, type FormEvent } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { CalendarDays, Clock3, Scissors, ArrowLeft, Loader2, XCircle, LogOut } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/BrandHeader";
import { Button } from "@/components/ui/button";
import { formatDateBR } from "@/lib/booking";

type Booking = {
  id: string;
  service_name: string;
  booking_date: string;
  booking_time: string;
};

export const Route = createFileRoute("/meus-agendamentos")({
  head: () => ({
    meta: [
      { title: "Meus agendamentos — Barbearia Bom Jesus" },
      { name: "description", content: "Consulte os próximos agendamentos na Barbearia Bom Jesus." },
    ],
  }),
  component: MeusAgendamentos,
});

function MeusAgendamentos() {
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [loading, setLoading] = useState(true);
  const [authBusy, setAuthBusy] = useState(false);
  const [cancellingId, setCancellingId] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setUserId(data.session?.user.id ?? null);
      if (!data.session) setLoading(false);
    });
    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUserId(session?.user.id ?? null);
    });
    return () => {
      mounted = false;
      authListener.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!userId) {
      setBookings([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    supabase
      .from("bookings")
      .select("id, service_name, booking_date, booking_time")
      .eq("user_id", userId)
      .not("status", "in", '("cancelado","concluido")')
      .gte("booking_date", new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" }))
      .order("booking_date")
      .order("booking_time")
      .then(({ data, error }) => {
        if (!active) return;
        if (error) {
          toast.error("Não foi possível carregar seus agendamentos. Tente novamente.");
          setBookings([]);
        } else {
          setBookings((data ?? []) as Booking[]);
        }
        setLoading(false);
      });
    return () => { active = false; };
  }, [userId]);

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAuthBusy(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });
    setAuthBusy(false);
    if (error) toast.error("E-mail ou senha inválidos.");
  }

  async function cancelBooking(booking: Booking) {
    const confirmed = window.confirm(
      `Cancelar ${booking.service_name} em ${formatDateBR(booking.booking_date)} às ${booking.booking_time}?`
    );
    if (!confirmed) return;

    setCancellingId(booking.id);
    const { data, error } = await supabase
      .from("bookings")
      .update({ status: "cancelado" })
      .eq("id", booking.id)
      .eq("user_id", userId!)
      .not("status", "in", '("cancelado","concluido")')
      .select("id")
      .maybeSingle();
    setCancellingId(null);

    if (error || !data) {
      toast.error("Não foi possível cancelar este agendamento. Tente novamente.");
      return;
    }
    toast.success("Agendamento cancelado.");
    setBookings((current) => current.filter((item) => item.id !== booking.id));
  }

  return (
    <div className="min-h-screen bg-background">
      <BrandHeader back />
      <main className="mx-auto max-w-2xl px-5 pb-16 pt-8 sm:px-8">
        <Link
          to="/agendar"
          search={{ servico: undefined }}
          className="inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-gold"
        >
          <ArrowLeft className="h-4 w-4" /> Voltar para agendamento
        </Link>

        <div className="mt-8">
          <p className="text-xs font-semibold uppercase tracking-[0.28em] text-gold">Área do cliente</p>
          <h1 className="mt-3 text-3xl font-bold text-foreground sm:text-4xl">Meus agendamentos</h1>
          <p className="mt-3 max-w-lg text-sm leading-relaxed text-muted-foreground">
            Entre com a mesma conta usada para reservar. Seus horários ficam protegidos e vinculados ao seu usuário.
          </p>
        </div>

        {!userId ? (
          <form onSubmit={signIn} className="mt-8 space-y-3 rounded-2xl border border-border bg-card p-5">
            <h2 className="font-semibold text-foreground">Entrar na sua conta</h2>
            <input
              required
              type="email"
              autoComplete="email"
              aria-label="E-mail"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="Seu e-mail"
              className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm outline-none focus:border-gold"
            />
            <input
              required
              type="password"
              autoComplete="current-password"
              aria-label="Senha"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Sua senha"
              className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm outline-none focus:border-gold"
            />
            <Button type="submit" disabled={authBusy} className="h-12 w-full gap-2 rounded-full bg-gold font-semibold text-gold-foreground">
              {authBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
              {authBusy ? "Entrando..." : "Entrar"}
            </Button>
            <p className="text-center text-xs text-muted-foreground">
              Ainda não tem conta? <Link to="/agendar" search={{ servico: undefined }} className="font-semibold text-gold">Crie ao confirmar seu próximo agendamento.</Link>
            </p>
          </form>
        ) : loading ? (
          <div className="mt-8 flex items-center justify-center gap-3 rounded-2xl border border-border bg-card p-8 text-sm text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin text-gold" /> Procurando seus agendamentos...
          </div>
        ) : bookings.length > 0 ? (
          <section className="mt-8">
            <div className="mb-4 flex items-center justify-between gap-3 text-sm text-muted-foreground">
              <span className="truncate">Conta conectada</span>
              <button type="button" onClick={() => void supabase.auth.signOut()} className="inline-flex shrink-0 items-center gap-2 text-xs font-semibold text-gold">
                <LogOut className="h-4 w-4" /> Sair
              </button>
            </div>
            <h2 className="text-xs font-semibold uppercase tracking-[0.25em] text-gold">Próximos horários</h2>
            <div className="mt-4 space-y-3">
              {bookings.map((booking) => (
                <article key={booking.id} className="rounded-2xl border border-border bg-card p-5">
                  <div className="flex items-start gap-3">
                    <div className="rounded-xl bg-gold/10 p-3 text-gold"><Scissors className="h-5 w-5" /></div>
                    <div className="min-w-0 flex-1">
                      <h3 className="font-semibold text-foreground">{booking.service_name}</h3>
                      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted-foreground">
                        <span className="inline-flex items-center gap-2"><CalendarDays className="h-4 w-4 text-gold" />{formatDateBR(booking.booking_date)}</span>
                        <span className="inline-flex items-center gap-2"><Clock3 className="h-4 w-4 text-gold" />{booking.booking_time}</span>
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        disabled={cancellingId === booking.id || cancellingId !== null}
                        onClick={() => void cancelBooking(booking)}
                        className="mt-4 gap-2 rounded-full border-destructive text-destructive hover:bg-destructive/10"
                      >
                        {cancellingId === booking.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <XCircle className="h-4 w-4" />}
                        {cancellingId === booking.id ? "Cancelando..." : "Cancelar agendamento"}
                      </Button>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          </section>
        ) : (
          <section className="mt-8 rounded-2xl border border-border bg-card p-6 text-center">
            <CalendarDays className="mx-auto h-8 w-8 text-gold" />
            <h2 className="mt-3 font-semibold text-foreground">Nenhum agendamento futuro</h2>
            <p className="mt-2 text-sm text-muted-foreground">Quando você confirmar uma reserva com esta conta, ela aparecerá aqui.</p>
            <Link to="/agendar" search={{ servico: undefined }} className="mt-5 inline-flex rounded-full bg-gold px-5 py-3 text-sm font-semibold text-gold-foreground">
              Agendar um horário
            </Link>
            <button type="button" onClick={() => void supabase.auth.signOut()} className="mx-auto mt-4 flex items-center gap-2 text-xs text-muted-foreground">
              <LogOut className="h-3.5 w-3.5" /> Sair da conta
            </button>
          </section>
        )}
      </main>
    </div>
  );
}
