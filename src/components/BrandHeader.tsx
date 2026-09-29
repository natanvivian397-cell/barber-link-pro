import { Link } from "@tanstack/react-router";
import logo from "@/assets/brothers-logo.png.asset.json";

export function BrandHeader({ back }: { back?: boolean }) {
  return (
    <header className="flex items-center justify-between px-6 pt-8 pb-2">
      <Link to="/" className="block">
        <img src={logo.url} alt="The Brother's Barber" className="h-14 w-auto" />
      </Link>
      {back ? (
        <Link
          to="/"
          className="rounded-full border border-border px-4 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-accent"
        >
          Voltar
        </Link>
      ) : null}
    </header>
  );
}
