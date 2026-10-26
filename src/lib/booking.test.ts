import { test } from "node:test";
import assert from "node:assert/strict";
import {
  availableSlots,
  isBookableDate,
  isHolidayBlockedDate,
  BOOKING_HORIZON_DAYS,
  type ScheduleDay,
} from "./booking";

const monday: ScheduleDay = { weekday: 1, is_open: true, morning_start: "09:00", morning_end: "12:00", afternoon_start: "13:00", afternoon_end: "19:00", slot_min: 30 };

test("a blocked interval is unavailable including services that overlap it", () => {
  const slots = availableSlots(monday, 40, [{ booking_time: "14:00", duration_min: 30 }], "2099-10-19");
  assert.equal(slots.includes("14:00"), false);
  assert.equal(slots.includes("13:30"), false);
  assert.equal(slots.includes("14:30"), true);
});

test("unblocking restores the slot", () => {
  assert.equal(availableSlots(monday, 40, [], "2099-10-19").includes("14:00"), true);
});

test("year-end and new-year dates are blocked", () => {
  assert.equal(isHolidayBlockedDate("2026-12-24"), true);
  assert.equal(isHolidayBlockedDate("2026-12-25"), true);
  assert.equal(isHolidayBlockedDate("2026-12-26"), true);
  assert.equal(isHolidayBlockedDate("2026-12-31"), true);
  assert.equal(isHolidayBlockedDate("2027-01-01"), true);
  assert.equal(isHolidayBlockedDate("2027-01-02"), true);
  assert.equal(isHolidayBlockedDate("2026-12-23"), false);
  assert.equal(isHolidayBlockedDate("2027-01-03"), false);
});

test("bookable horizon is 30 days and excludes holidays", () => {
  const days: ScheduleDay[] = Array.from({ length: 7 }, (_, i) => ({
    weekday: i,
    is_open: true,
    morning_start: "09:00",
    morning_end: "12:00",
    afternoon_start: "13:00",
    afternoon_end: "19:00",
    slot_min: 30,
  }));
  const today = new Date();
  const toISO = (d: Date) => {
    const offset = d.getTimezoneOffset();
    return new Date(d.getTime() - offset * 60000).toISOString().slice(0, 10);
  };
  const todayISO = toISO(today);
  const in30 = new Date(today);
  in30.setDate(in30.getDate() + 30);
  assert.equal(isBookableDate(todayISO, days), true);
  assert.equal(isBookableDate(toISO(in30), days), true);
  const future = new Date(today);
  future.setDate(future.getDate() + 60);
  assert.equal(isBookableDate(toISO(future), days), false);
  assert.equal(isBookableDate("2026-12-24", days), false);
  assert.equal(isBookableDate("2027-01-01", days), false);
  assert.equal(BOOKING_HORIZON_DAYS, 30);
});
