import { useState, type FormEvent } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { CalendarDays, Clock3, Search, Scissors, ArrowLeft, Loader2 } from "lucide-react";
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
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [loading, setLoading] = useState(false);

  async function searchBookings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (name.trim().length < 2 || phone.replace(/\D/g, "").length < 10) {
      toast.error("Informe o nome e o WhatsApp usados no agendamento.");
      return;
    }

    setLoading(true);
    const { data, error } = await supabase.rpc("find_my_bookings", {
      _name: name.trim(),
      _phone: phone.trim(),
    });
    setLoading(false);

    if (error) {
      toast.error("Não foi possível consultar seus agendamentos. Tente novamente.");
      return;
    }
    setBookings((data ?? []) as Booking[]);
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
            Consulte seus próximos horários usando o mesmo nome e WhatsApp informados ao agendar.
          </p>
        </div>

        <form onSubmit={searchBookings} className="mt-8 space-y-3 rounded-2xl border border-border bg-card p-5">
          <label className="block">
            <span className="mb-2 block text-xs font-medium text-muted-foreground">Nome usado no agendamento</span>
            <input
              aria-label="Nome usado no agendamento"
              autoComplete="name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Seu nome completo"
              className="w-full rounded-full border border-border bg-background px-5 py-3.5 text-sm text-foreground outline-none focus:border-gold"
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-xs font-medium text-muted-foreground">WhatsApp usado no agendamento</span>
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
            disabled={loading}
            className="h-12 w-full gap-2 rounded-full bg-gold font-semibold text-gold-foreground hover:bg-gold/90"
          >
            {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
            {loading ? "Buscando..." : "Consultar agendamentos"}
          </Button>
        </form>

        {bookings !== null ? (
          <section className="mt-8">
            <h2 className="text-xs font-semibold uppercase tracking-[0.25em] text-gold">
              Próximos horários
            </h2>
            {bookings.length === 0 ? (
              <div className="mt-4 rounded-2xl border border-border bg-card px-5 py-8 text-center">
                <CalendarDays className="mx-auto h-8 w-8 text-muted-foreground" />
                <p className="mt-3 font-medium text-foreground">Nenhum agendamento encontrado</p>
                <p className="mt-2 text-sm text-muted-foreground">
                  Confira se digitou o mesmo nome e WhatsApp usados na reserva.
                </p>
                <Link
                  to="/agendar"
                  search={{ servico: undefined }}
                  className="mt-5 inline-flex rounded-full bg-gold px-5 py-3 text-sm font-semibold text-gold-foreground"
                >
                  Agendar um horário
                </Link>
              </div>
            ) : (
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
                      </div>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </section>
        ) : null}
      </main>
    </div>
  );
}
