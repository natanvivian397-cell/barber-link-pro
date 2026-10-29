const STORAGE_KEY = "barber-link-pro-device-token";

/**
 * A random, per-browser identifier used only to find bookings on this device.
 * It is a convenience token, not a replacement for strong account authentication.
 */
export function getDeviceToken(): string {
  if (typeof window === "undefined") return "";
  let token = window.localStorage.getItem(STORAGE_KEY);
  if (!token) {
    token = `${window.crypto.randomUUID()}-${window.crypto.randomUUID()}`;
    window.localStorage.setItem(STORAGE_KEY, token);
  }
  return token;
}
