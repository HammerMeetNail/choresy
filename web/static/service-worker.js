const CACHE_NAME = "nabu-static-v1";
const OFFLINE_URL = "/static/offline.html";
const STATIC_ASSETS = [
  "/static/css/app.css",
  "/static/js/app.js",
  "/static/js/state.js",
  "/static/js/morph.js",
  "/static/js/api.js",
  "/static/manifest.webmanifest",
  "/static/icons/icon.svg",
  OFFLINE_URL,
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(STATIC_ASSETS);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("pushsubscriptionchange", (event) => {
  const ts = Date.now();
  self.__diag = self.__diag || [];
  self.__diag.push({ type: "subscriptionchange", ts, old: !!event.oldSubscription, new: !!event.newSubscription });
});

self.addEventListener("push", (event) => {
  const ts = Date.now();
  let data = {};
  let decrypted = false;
  let hasData = !!event.data;
  try {
    if (event.data) {
      data = event.data.json();
      decrypted = true;
    }
  } catch (e) {
    self.__diag = self.__diag || [];
    self.__diag.push({ type: "push-decode-error", ts, msg: e.message });
  }
  const title = data.title || "Nabu";
  const body = data.body || "";
  const icon = "/static/icons/icon-192.png";
  self.lastPush = { decrypted, title, body, time: ts, hasData };
  self.__diag = self.__diag || [];
  self.__diag.push({ type: "push-received", ts, decrypted, hasData });
  self.__badgeCount = (self.__badgeCount || 0) + 1;

  // Chore reminders carry a choreId so we can offer a "Log now" action that
  // deep-links straight to the pre-filled log sheet. Actions render on
  // Android/Chromium and iOS 16.4+ web push.
  const notifData = { choreId: data.choreId || null, type: data.type || null };
  const options = {
    body: body || "(tap to open)",
    icon,
    tag: "nabu",
    requireInteraction: true,
    vibrate: [200, 100, 200],
    data: notifData,
  };
  if (data.type === "schedule_reminder" && data.choreId) {
    options.actions = [
      { action: "log-now", title: "✓ Log now" },
      { action: "snooze", title: "⏰ Snooze 30m" },
    ];
  }
  event.waitUntil(
    Promise.all([
      self.registration.showNotification(title, options),
      setBadge(self.__badgeCount),
    ])
  );
});

self.addEventListener("message", (event) => {
  if (event.data === "last-push") {
    event.ports[0].postMessage(self.lastPush || {});
  }
  if (event.data === "push-diag") {
    event.ports[0].postMessage({
      lastPush: self.lastPush || null,
      diag: self.__diag || [],
      registration: !!self.registration,
    });
  }
  if (event.data === "clear-badge") {
    self.__badgeCount = 0;
    event.waitUntil(clearBadge());
  }
});

async function setBadge(count) {
  const ua = self.navigator && self.navigator.userAgent ? self.navigator.userAgent : "";
  if (/HeadlessChrome|HeadlessShell/i.test(ua)) {
    return;
  }
  try {
    if ("setAppBadge" in self.navigator) {
      await self.navigator.setAppBadge(count);
    }
  } catch { /* not supported */ }
}

async function clearBadge() {
  const ua = self.navigator && self.navigator.userAgent ? self.navigator.userAgent : "";
  if (/HeadlessChrome|HeadlessShell/i.test(ua)) {
    return;
  }
  try {
    if ("clearAppBadge" in self.navigator) {
      await self.navigator.clearAppBadge();
    }
  } catch { /* not supported */ }
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};

  // "Snooze 30m" silently reschedules the reminder without opening the app.
  // The fetch carries the session cookie automatically (same-origin); the
  // endpoint is CSRF-exempt and ownership-checked server-side.
  if (event.action === "snooze" && data.choreId) {
    event.waitUntil(
      fetch("/api/reminders/snooze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ choreId: data.choreId, minutes: 30 }),
      }).catch(() => {})
    );
    return;
  }

  // "Log now" deep-links to the pre-filled log sheet for the reminder's chore.
  // A plain body tap (no action) just opens/focuses the app.
  const wantsLog = event.action === "log-now" && data.choreId;
  const targetUrl = wantsLog ? `/?quicklog=chore:${data.choreId}` : "/";
  event.waitUntil(
    Promise.all([
      clearBadge(),
      self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
        for (const client of clientList) {
          if (client.focus) {
            if (wantsLog && client.postMessage) {
              client.postMessage({ type: "quicklog", choreId: data.choreId });
            }
            return client.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(targetUrl);
        }
      }),
    ])
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") {
    return;
  }

  const requestURL = new URL(event.request.url);
  if (requestURL.origin !== self.location.origin) {
    return;
  }

  if (event.request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        return await fetch(event.request);
      } catch {
        const cache = await caches.open(CACHE_NAME);
        return await cache.match(OFFLINE_URL) || Response.error();
      }
    })());
    return;
  }

  if (!requestURL.pathname.startsWith("/static/")) {
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(event.request);
    if (cached) {
      void fetch(event.request).then((response) => {
        if (response && response.ok) {
          void cache.put(event.request, response.clone());
        }
      }).catch(() => {});
      return cached;
    }
    const response = await fetch(event.request);
    if (response && response.ok) {
      await cache.put(event.request, response.clone());
    }
    return response;
  })());
});
