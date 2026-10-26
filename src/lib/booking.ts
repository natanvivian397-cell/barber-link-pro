export type Service = {
  id: string;
  photo_path: string | null;
  name: string;
  description: string | null;
  price: number;
  duration_min: number;
  sort_order: number;
};

export type Barber = { id: string; name: string; active: boolean; sort_order: number; photo_path: string | null };

export type Booking = {
  id: string;
  barber_id: string | null;
  duration_min: number;
  customer_name: string;
  customer_phone: string;
  service_name: string;
  price: number;
  booking_date: string;
  booking_time: string;
  notes: string | null;
  status: string;
  created_at: string;
};

export type ScheduleDay = {
  weekday: number;
  is_open: boolean;
  morning_start: string;
  morning_end: string;
  afternoon_start: string;
  afternoon_end: string;
  slot_min: number;
};

export const WEEKDAY_NAMES = [
  "Domingo",
  "Segunda",
  "Terça",
  "Quarta",
  "Quinta",
  "Sexta",
  "Sábado",
];

function toMinutes(hhmm: string) {
  const [h, m] = hhmm.split(":");
  return Number(h) * 60 + Number(m ?? 0);
}

function toHHMM(total: number) {
  const h = Math.floor(total / 60);
  const m = total % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export function buildSlots(day: ScheduleDay | undefined): string[] {
  if (!day || !day.is_open) return [];
  const step = Math.max(5, day.slot_min || 30);
  const slots: string[] = [];
  const ranges: [string, string][] = [
    [day.morning_start, day.morning_end],
    [day.afternoon_start, day.afternoon_end],
  ];
  for (const [from, to] of ranges) {
    const start = toMinutes(from);
    const end = toMinutes(to);
    for (let t = start; t + step <= end; t += step) slots.push(toHHMM(t));
  }
  return Array.from(new Set(slots)).sort();
}

export type Taken = { booking_time: string; duration_min: number };

/** Horários livres considerando a duração do serviço e os agendamentos existentes. */
export function availableSlots(
  day: ScheduleDay | undefined,
  duration: number,
  taken: Taken[],
  dateISO: string,
): string[] {
  if (!day || !day.is_open) return [];
  const step = Math.max(5, day.slot_min || 30);
  const dur = Math.max(5, duration || step);
  const busy = taken.map((t) => {
    const s = toMinutes(t.booking_time);
    return [s, s + (t.duration_min || 30)] as const;
  });
  let minStart = -1;
  if (dateISO === todayISO()) {
    const n = new Date();
    minStart = n.getHours() * 60 + n.getMinutes();
  }
  const out: string[] = [];
  const ranges: [string, string][] = [
    [day.morning_start, day.morning_end],
    [day.afternoon_start, day.afternoon_end],
  ];
  for (const [from, to] of ranges) {
    const start = toMinutes(from);
    const end = toMinutes(to);
    for (let t = start; t + dur <= end; t += step) {
      if (t <= minStart) continue;
      if (busy.some(([s, e]) => s < t + dur && e > t)) continue;
      out.push(toHHMM(t));
    }
  }
  return Array.from(new Set(out)).sort();
}

export const BOOKING_HORIZON_DAYS = 30;

export const HOLIDAY_BLOCKED_DATES = new Set<string>([
  "2026-12-24",
  "2026-12-25",
  "2026-12-26",
  "2026-12-31",
  "2027-01-01",
  "2027-01-02",
  "2027-12-24",
  "2027-12-25",
  "2027-12-26",
  "2027-12-31",
  "2028-01-01",
  "2028-01-02",
  "2028-12-24",
  "2028-12-25",
  "2028-12-26",
  "2028-12-31",
  "2029-01-01",
  "2029-01-02",
]);

export function isHolidayBlockedDate(iso: string) {
  if (HOLIDAY_BLOCKED_DATES.has(iso)) return true;
  const [y, m, d] = iso.split("-").map(Number);
  if (!y || !m || !d) return false;
  const md = `${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  return (
    md === "12-24" ||
    md === "12-25" ||
    md === "12-26" ||
    md === "12-31" ||
    md === "01-01" ||
    md === "01-02"
  );
}

export function isBookableDate(dateISO: string, openDays: ScheduleDay[] | undefined) {
  if (isHolidayBlockedDate(dateISO)) return false;
  const day = openDays?.find((d) => d.weekday === weekdayOfISO(dateISO));
  if (!day || !day.is_open) return false;
  const start = todayISO();
  const end = addDaysISO(todayISO(), BOOKING_HORIZON_DAYS);
  return dateISO >= start && dateISO <= end;
}

export function addDaysISO(iso: string, n: number) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y ?? 2000, (m ?? 1) - 1, (d ?? 1) + n)).toISOString().slice(0, 10);
}

export function weekdayOfISO(iso: string) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y ?? 2000, (m ?? 1) - 1, d ?? 1)).getUTCDay();
}

export const TIME_SLOTS = [
  "09:00",
  "09:40",
  "10:20",
  "11:00",
  "11:40",
  "13:30",
  "14:10",
  "14:50",
  "15:30",
  "16:10",
  "16:50",
  "17:30",
  "18:10",
  "18:50",
  "19:30",
];

export function formatBRL(value: number) {
  return value.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function todayISO() {
  const now = new Date();
  const offset = now.getTimezoneOffset();
  return new Date(now.getTime() - offset * 60000).toISOString().slice(0, 10);
}

export function formatDateBR(iso: string) {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}
