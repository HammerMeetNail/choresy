// Duration timer (Phase 5.2). A single active timer is persisted in
// localStorage so it survives reloads. Pure helpers here; the DOM chip and
// action wiring live in app.js.

const KEY = "nabu_active_timer";

// loadTimer returns the persisted active timer, or null. It validates shape so
// a corrupt/partial value never crashes the caller.
export function loadTimer() {
  try {
    if (typeof localStorage === "undefined") return null;
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const t = JSON.parse(raw);
    if (t && typeof t.choreId === "number" && typeof t.startedAt === "number") {
      return t;
    }
  } catch { /* ignore */ }
  return null;
}

// saveTimer persists (or clears, when t is falsy) the active timer.
export function saveTimer(t) {
  try {
    if (typeof localStorage === "undefined") return;
    if (t) localStorage.setItem(KEY, JSON.stringify(t));
    else localStorage.removeItem(KEY);
  } catch { /* ignore */ }
}

// elapsedSeconds returns whole seconds elapsed since the timer started.
export function elapsedSeconds(t, now = Date.now()) {
  if (!t || typeof t.startedAt !== "number") return 0;
  return Math.max(0, Math.floor((now - t.startedAt) / 1000));
}

// formatElapsed renders seconds as m:ss (or h:mm:ss past an hour).
export function formatElapsed(sec) {
  const s = Math.max(0, Math.floor(sec || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const pad = (n) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(ss)}` : `${m}:${pad(ss)}`;
}
