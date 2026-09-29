import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, CalendarDays, ChevronRight } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/BrandHeader";
import { formatBRL, type Service } from "@/lib/booking";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Barbearia Bom Jesus — Agende seu horário" },
      {
        name: "description",
        content:
          "Escolha o serviço, veja o valor e agende seu horário na Barbearia Bom Jesus em poucos cliques.",
      },
      { property: "og:title", content: "Barbearia Bom Jesus — Agende seu horário" },
      {
        property: "og:description",
        content: "Corte, barba, pigmentação, platinado e mais. Agendamento online em poucos cliques.",
      },
    ],
  }),
  component: Index,
});

function Index() {
  const { data: services, isLoading } = useQuery({
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

  return (
    <div className="min-h-screen pb-28">
      <BrandHeader />

      <section className="px-6 pt-6">
        <p className="eyebrow">Agende seu horário</p>
        <h1 className="mt-3 text-4xl font-bold leading-[1.05] text-foreground sm:text-5xl">
          Seu estilo,
          <br />
          nossa especialidade.
        </h1>
        <p className="mt-4 max-w-sm text-base leading-relaxed text-muted-foreground">
          Escolha o serviço, veja o valor e agende em poucos cliques.
        </p>
      </section>

      <section className="px-6 pt-10">
        <p className="eyebrow">Nossos serviços</p>
        <div className="mt-4 space-y-3">
          {isLoading
            ? Array.from({ length: 6 }).map((_, i) => (
                <div key={i} className="h-[76px] animate-pulse rounded-2xl bg-muted" />
              ))
            : services?.map((s) => (
                <Link
                  key={s.id}
                  to="/agendar"
                  search={{ servico: s.id }}
                  className="flex items-center justify-between gap-4 rounded-2xl border border-border bg-card px-5 py-4 shadow-card transition-transform active:scale-[0.99]"
                >
                  <div className="min-w-0">
                    <p className="truncate text-[15px] font-semibold text-foreground">{s.name}</p>
                    <p className="truncate text-[13px] text-muted-foreground">{s.description}</p>
                  </div>
                  <div className="flex shrink-0 items-baseline gap-1.5">
                    <span className="text-[11px] text-muted-foreground">R$</span>
                    <span className="text-lg font-bold text-foreground">{formatBRL(s.price)}</span>
                    <ChevronRight className="h-4 w-4 translate-y-0.5 text-muted-foreground" />
                  </div>
                </Link>
              ))}
        </div>
      </section>

      <div className="fixed inset-x-0 bottom-0 bg-gradient-to-t from-background via-background to-transparent px-6 pb-6 pt-8">
        <Link
          to="/agendar"
          search={{ servico: undefined }}

          className="mx-auto flex max-w-xl items-center justify-between gap-3 rounded-full bg-primary px-7 py-4 text-primary-foreground shadow-float transition-transform active:scale-[0.99]"
        >
          <CalendarDays className="h-5 w-5" />
          <span className="text-sm font-semibold tracking-[0.12em]">AGENDAR HORÁRIO</span>
          <ArrowRight className="h-5 w-5" />
        </Link>
      </div>
    </div>
  );
}
