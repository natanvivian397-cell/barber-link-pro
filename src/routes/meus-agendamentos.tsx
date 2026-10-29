import { useEffect, useState, type FormEvent } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { CalendarDays, Clock3, Scissors, ArrowLeft, Loader2, Smartphone, XCircle } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { getDeviceToken } from "@/lib/deviceIdentity";
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
  const [deviceToken, setDeviceToken] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [claiming, setClaiming] = useState(false);
  const [cancellingId, setCancellingId] = useState<string | null>(null);

  async function loadDeviceBookings(token: string) {
    const { data, error } = await supabase.rpc("find_my_bookings_by_device", {
      _device_token: token,
    });
    if (error) {
      toast.error("Não foi possível carregar seus agendamentos. Tente novamente.");
      setBookings([]);
      return;
    }
    setBookings((data ?? []) as Booking[]);
  }

  useEffect(() => {
    const token = getDeviceToken();
    setDeviceToken(token);
    if (!token) {
      setLoading(false);
      toast.error("Não foi possível reconhecer este dispositivo.");
      return;
    }
    void loadDeviceBookings(token).finally(() => setLoading(false));
  }, []);

  async function cancelBooking(booking: Booking) {
    if (!deviceToken) {
      toast.error("Este dispositivo ainda não pôde ser identificado.");
      return;
    }
    const confirmed = window.confirm(
      `Cancelar ${booking.service_name} em ${formatDateBR(booking.booking_date)} às ${booking.booking_time}?`
    );
    if (!confirmed) return;

    setCancellingId(booking.id);
    const { data, error } = await supabase.rpc("cancel_my_booking_by_device", {
      _booking_id: booking.id,
      _device_token: deviceToken,
    });
    setCancellingId(null);

    if (error || !data) {
      toast.error("Não foi possível cancelar este agendamento. Tente novamente.");
      return;
    }
    toast.success("Agendamento cancelado.");
    setBookings((current) => (current ?? []).filter((item) => item.id !== booking.id));
  }

  async function linkPreviousBookings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (name.trim().length < 2 || phone.replace(/\D/g, "").length < 10) {
      toast.error("Informe o nome e o WhatsApp usados no agendamento.");
      return;
    }
    if (!deviceToken) {
      toast.error("Este dispositivo ainda não pôde ser identificado.");
      return;
    }

    setClaiming(true);
    const { data, error } = await supabase.rpc("claim_my_bookings_for_device", {
      _name: name.trim(),
      _phone: phone.trim(),
      _device_token: deviceToken,
    });
    if (error) {
      setClaiming(false);
      toast.error("Não foi possível vincular seus agendamentos. Tente novamente.");
      return;
    }

    await loadDeviceBookings(deviceToken);
    setClaiming(false);
    if ((data ?? 0) > 0) {
      toast.success("Pronto! Seus agendamentos foram vinculados a este dispositivo.");
    } else {
      toast.info("Não encontramos agendamentos futuros com esses dados.");
    }
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
            Seus horários aparecem automaticamente quando você acessa pelo mesmo dispositivo usado para agendar.
          </p>
        </div>

        {loading ? (
          <div className="mt-8 flex items-center justify-center gap-3 rounded-2xl border border-border bg-card p-8 text-sm text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin text-gold" /> Procurando seus agendamentos...
          </div>
        ) : bookings && bookings.length > 0 ? (
          <section className="mt-8">
            <div className="mb-4 flex items-center gap-2 text-sm text-muted-foreground">
              <Smartphone className="h-4 w-4 text-gold" /> Dispositivo reconhecido
            </div>
            <h2 className="text-xs font-semibold uppercase tracking-[0.25em] text-gold">Próximos horários</h2>
            <div className="mt-4 space-y-3">
              {bookings.map((booking) => (
                <article key={booking.id} className="rounded-2xl border border-border bg-card p-5">
                  <div className="flex items-start gap-3">
                    <div className="rounded-xl bg-gold/10 p-3 text-gold">
                      <Scissors className="h-5 w-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <h3 className="font-semibold text-foreground">{booking.service_name}</h3>
                      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted-foreground">
                        <span className="inline-flex items-center gap-2">
                          <CalendarDays className="h-4 w-4 text-gold" />
                          {formatDateBR(booking.booking_date)}
                        </span>
                        <span className="inline-flex items-center gap-2">
                          <Clock3 className="h-4 w-4 text-gold" />
                          {booking.booking_time}
                        </span>
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
          <section className="mt-8 rounded-2xl border border-border bg-card p-5">
            <div className="text-center">
              <Smartphone className="mx-auto h-8 w-8 text-gold" />
              <h2 className="mt-3 font-semibold text-foreground">Nenhum agendamento vinculado a este dispositivo</h2>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                Os próximos agendamentos feitos neste dispositivo aparecerão aqui automaticamente. Se você já tinha uma reserva, vincule-a uma única vez abaixo.
              </p>
              <Link
                to="/agendar"
                search={{ servico: undefined }}
                className="mt-5 inline-flex rounded-full bg-gold px-5 py-3 text-sm font-semibold text-gold-foreground"
              >
                Agendar um horário
              </Link>
            </div>

            <form onSubmit={linkPreviousBookings} className="mt-7 space-y-3 border-t border-border pt-6">
              <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-gold">Já tinha um agendamento?</h3>
              <p className="text-sm text-muted-foreground">
                Preencha estes dados apenas uma vez para vincular suas reservas antigas a este dispositivo.
              </p>
              <label className="block">
                <span className="mb-2 block text-xs font-medium text-muted-foreground">Nome usado na reserva</span>
                <input
                  aria-label="Nome usado no agendamento"
                  autoComplete="name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder="Seu nome (pode ser o primeiro nome)"
                  className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm text-foreground outline-none focus:border-gold"
                />
              </label>
              <label className="block">
                <span className="mb-2 block text-xs font-medium text-muted-foreground">WhatsApp usado na reserva</span>
                <input
                  aria-label="WhatsApp usado no agendamento"
                  autoComplete="tel"
                  inputMode="tel"
                  value={phone}
                  onChange={(event) => setPhone(event.target.value)}
                  placeholder="(51) 9 9999-9999"
                  className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm text-foreground outline-none focus:border-gold"
                />
              </label>
              <Button
                type="submit"
                disabled={claiming || loading}
                className="h-12 w-full gap-2 rounded-full bg-gold font-semibold text-gold-foreground hover:bg-gold/90"
              >
                {claiming ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                {claiming ? "Vinculando..." : "Vincular meus agendamentos"}
              </Button>
            </form>
          </section>
        )}
      </main>
    </div>
  );
}
