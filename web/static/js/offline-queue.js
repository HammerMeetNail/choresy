// Offline log queue.
//
// The service worker only caches GET requests, so a POST /api/logs made while
// offline (e.g. a 3am feed on flaky reception) would otherwise fail and lose
// the log — the worst failure for the baby use case where the timestamp
// matters. This module persists failed/offline log mutations in IndexedDB and
// replays them when connectivity returns. Each queued item carries a
// client-generated idempotencyKey so replay is safe against duplicates (the
// server de-dups on it).

const DB_NAME = "nabu-offline";
const DB_VERSION = 1;
const STORE = "logQueue";

function hasIDB() {
  return typeof indexedDB !== "undefined" && indexedDB !== null;
}

function openDB() {
  return new Promise((resolve, reject) => {
    if (!hasIDB()) { reject(new Error("indexeddb-unavailable")); return; }
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: "idempotencyKey" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// enqueueLog stores a log POST body (which must include an idempotencyKey) for
// later replay. Idempotent on the key, so re-enqueuing the same attempt
// overwrites rather than duplicates.
export async function enqueueLog(body) {
  if (!body || !body.idempotencyKey) return false;
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put({ ...body, _queuedAt: Date.now() });
    tx.oncomplete = () => resolve(true);
    tx.onerror = () => reject(tx.error);
  });
}

export async function queuedCount() {
  try {
    const db = await openDB();
    return await new Promise((resolve) => {
      const tx = db.transaction(STORE, "readonly");
      const req = tx.objectStore(STORE).count();
      req.onsuccess = () => resolve(req.result || 0);
      req.onerror = () => resolve(0);
    });
  } catch {
    return 0;
  }
}

function getAll(db) {
  return new Promise((resolve) => {
    const tx = db.transaction(STORE, "readonly");
    const req = tx.objectStore(STORE).getAll();
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => resolve([]);
  });
}

function deleteItem(db, key) {
  return new Promise((resolve) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => resolve();
  });
}

// replayQueue attempts to POST every queued log via the given apiFetch. On a
// 2xx (including an idempotent replay hit) the item is removed. A permanent
// client error (4xx other than 429) also removes the item to avoid an infinite
// retry loop. A network failure stops the pass, leaving remaining items for a
// later attempt. Returns the number successfully synced.
export async function replayQueue(apiFetch) {
  let db;
  try { db = await openDB(); } catch { return 0; }
  const items = await getAll(db);
  let synced = 0;
  for (const item of items) {
    const { _queuedAt, ...body } = item;
    try {
      const { response } = await apiFetch("/api/logs", {
        method: "POST",
        body: JSON.stringify(body),
      });
      if (response && response.ok) {
        await deleteItem(db, item.idempotencyKey);
        synced++;
      } else if (response && response.status >= 400 && response.status < 500 && response.status !== 429) {
        // Permanent client error (e.g. the chore was deleted) — drop it.
        await deleteItem(db, item.idempotencyKey);
      }
      // 5xx / 429: keep and try again next time.
    } catch {
      // Still offline — stop; keep the rest queued.
      break;
    }
  }
  return synced;
}
