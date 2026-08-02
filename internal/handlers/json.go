package handlers

import (
	"encoding/json"
	"log"
	"net/http"
)

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

// writeServerError is the only sanctioned way to surface a 5xx: it logs the
// real error server-side (never request bodies or PII) and returns a static,
// user-facing message so pgx/store internals never leak to API clients. The
// message doubles as the log context prefix.
func writeServerError(w http.ResponseWriter, message string, err error) {
	log.Printf("%s: %v", message, err)
	writeError(w, http.StatusInternalServerError, message)
}

func readJSON(r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20) // 1 MB
	return json.NewDecoder(r.Body).Decode(target)
}
