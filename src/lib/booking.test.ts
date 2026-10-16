import { test, expect } from "bun:test";
import { availableSlots, type ScheduleDay } from "./booking";

const monday: ScheduleDay = { weekday: 1, is_open: true, morning_start: "09:00", morning_end: "12:00", afternoon_start: "13:00", afternoon_end: "19:00", slot_min: 30 };

test("a blocked interval is unavailable including services that overlap it", () => {
  const slots = availableSlots(monday, 40, [{ booking_time: "14:00", duration_min: 30 }], "2099-10-19");
  expect(slots).not.toContain("14:00");
  expect(slots).not.toContain("13:30");
  expect(slots).toContain("14:30");
});

test("unblocking restores the slot", () => {
  expect(availableSlots(monday, 40, [], "2099-10-19")).toContain("14:00");
});