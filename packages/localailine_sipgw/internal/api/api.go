// Package api is the gateway's control API: HTTP/JSON, a bearer token on every request
// except /healthz, compared in constant time, and failed tokens rate limited per address.
//
//	PUT    /v1/accounts/{id}        add or change a line (password optional on change)
//	DELETE /v1/accounts/{id}        remove a line (signs it out first)
//	GET    /v1/accounts/{id}        one line and its status (never the password)
//	GET    /v1/accounts             every line
//	POST   /v1/accounts/{id}/test   one REGISTER attempt; the outcome in plain words
//	GET    /healthz                 200 when running
//	GET    /metrics                 Prometheus text
package api

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/ratelimit"
)

// Backend is what the API controls (the gateway).
type Backend interface {
	Upsert(a account.Account) (account.View, error)
	Delete(id string) bool
	Get(id string) (account.View, bool)
	List() []account.View
	Test(ctx context.Context, id string) (ok bool, words string, found bool)
	WriteMetrics(w io.Writer)
}

// ErrInvalid wraps a validation error (answered 400).
type ErrInvalid struct{ Err error }

func (e ErrInvalid) Error() string { return e.Err.Error() }

// Server is the HTTP handler.
type Server struct {
	b         Backend
	tokenHash [32]byte
	fails     *ratelimit.Limiter
	log       *slog.Logger
	metrics   *metrics.Metrics
	mux       *http.ServeMux
}

// New makes the API for b, accepting bearer token.
func New(b Backend, token string, m *metrics.Metrics, log *slog.Logger) *Server {
	s := &Server{
		b: b, tokenHash: sha256.Sum256([]byte(token)),
		fails: ratelimit.New(1.0/6, 10), // 10 wrong tokens, then one more every 6 seconds
		log:   log, metrics: m, mux: http.NewServeMux(),
	}
	s.mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})
	s.mux.Handle("GET /metrics", s.auth(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		b.WriteMetrics(w)
	}))
	s.mux.Handle("GET /v1/accounts", s.auth(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"accounts": b.List()})
	}))
	s.mux.Handle("GET /v1/accounts/{id}", s.auth(func(w http.ResponseWriter, r *http.Request) {
		v, ok := b.Get(r.PathValue("id"))
		if !ok {
			writeErr(w, 404, "no such account")
			return
		}
		writeJSON(w, 200, v)
	}))
	s.mux.Handle("PUT /v1/accounts/{id}", s.auth(func(w http.ResponseWriter, r *http.Request) {
		var a account.Account
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&a); err != nil {
			writeErr(w, 400, "body must be a JSON account: "+cleanJSONError(err))
			return
		}
		id := r.PathValue("id")
		if a.ID != "" && a.ID != id {
			writeErr(w, 400, "id in the body does not match the URL")
			return
		}
		a.ID = id
		v, err := b.Upsert(a)
		var inv ErrInvalid
		if errors.As(err, &inv) {
			writeErr(w, 400, inv.Error())
			return
		}
		if err != nil {
			s.log.Error("saving account failed", "line", id, "error", err)
			writeErr(w, 500, "could not save the account")
			return
		}
		writeJSON(w, 200, v)
	}))
	s.mux.Handle("DELETE /v1/accounts/{id}", s.auth(func(w http.ResponseWriter, r *http.Request) {
		if !b.Delete(r.PathValue("id")) {
			writeErr(w, 404, "no such account")
			return
		}
		w.WriteHeader(204)
	}))
	s.mux.Handle("POST /v1/accounts/{id}/test", s.auth(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		ok, words, found := b.Test(ctx, r.PathValue("id"))
		if !found {
			writeErr(w, 404, "no such account")
			return
		}
		writeJSON(w, 200, map[string]any{"ok": ok, "result": words})
	}))
	return s
}

// ServeHTTP serves the API.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	s.mux.ServeHTTP(w, r)
}

// auth checks the bearer token in constant time; too many wrong tokens from one address
// are refused (429) before even checking.
func (s *Server) auth(h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		if s.fails.Blocked(ip) {
			w.Header().Set("Retry-After", "10")
			writeErr(w, 429, "too many wrong tokens; wait and try again")
			return
		}
		tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		got := sha256.Sum256([]byte(strings.TrimSpace(tok)))
		if !ok || subtle.ConstantTimeCompare(got[:], s.tokenHash[:]) != 1 {
			s.fails.Allow(ip)
			if s.metrics != nil {
				s.metrics.ControlAuthFailed.Add(1)
			}
			s.log.Debug("control API: wrong or missing token", "remote", ip)
			w.Header().Set("WWW-Authenticate", `Bearer realm="sipgw"`)
			writeErr(w, 401, "missing or wrong bearer token")
			return
		}
		h(w, r)
	})
}

func clientIP(r *http.Request) string {
	h, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return h
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

// cleanJSONError keeps decoder errors short and free of request content.
func cleanJSONError(err error) string {
	var se *json.SyntaxError
	var te *json.UnmarshalTypeError
	switch {
	case errors.As(err, &se):
		return "invalid JSON"
	case errors.As(err, &te):
		return "field " + te.Field + " has the wrong type"
	case strings.HasPrefix(err.Error(), "json: unknown field"):
		return strings.TrimPrefix(err.Error(), "json: ")
	case errors.Is(err, io.EOF):
		return "empty body"
	}
	return "unreadable body"
}
