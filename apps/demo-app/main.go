// Command demo-app is the example app for the platform take-home challenge. It is
// a small Sefaria search web app (search logic borrowed from the chofesh CLI):
// a form runs a search against the Sefaria API, prints the results in-page, and
// persists both the query+results and a log of every outbound API call to the
// CloudNativePG-managed Postgres — so the database and the dashboards show real,
// continuous activity. App-level Prometheus metrics are exposed at /metrics.
//
// All connection details come from the environment (DATABASE_URL, wired from the
// CNPG-generated `pg-app` secret) — no credentials in the image or manifests. The
// schema is created idempotently at startup with bounded retries.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/ryderdain/barzel-cluster/apps/demo-app/internal/sefaria"
)

// schema is applied at startup; IF NOT EXISTS keeps it idempotent across the
// rolling pod restarts ArgoCD drives. `items` is retained from the original
// read/write demo; the search tables are the Sefaria app's domain.
const schema = `
CREATE TABLE IF NOT EXISTS items (
	id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name       text NOT NULL,
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS searches (
	id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	query      text NOT NULL,
	field      text NOT NULL,
	size       int  NOT NULL,
	hit_count  int  NOT NULL,
	took_ms    int  NOT NULL,
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS search_results (
	id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	search_id  bigint NOT NULL REFERENCES searches(id) ON DELETE CASCADE,
	rank       int  NOT NULL,
	ref        text NOT NULL,
	he_ref     text,
	snippet    text,
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS api_calls (
	id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	method      text NOT NULL,
	url         text NOT NULL,
	status      int  NOT NULL,
	duration_ms int  NOT NULL,
	created_at  timestamptz NOT NULL DEFAULT now()
);`

type server struct {
	pool    *pgxpool.Pool
	log     *slog.Logger
	metrics *metrics
	sefaria *sefaria.Client
	ready   atomic.Bool
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Error("DATABASE_URL is required (wire it from the CNPG pg-app secret)")
		os.Exit(1)
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Error("invalid DATABASE_URL", "err", err)
		os.Exit(1)
	}
	cfg.MaxConns = 10
	cfg.ConnConfig.RuntimeParams["application_name"] = "demo-app"

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Error("create connection pool", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	srv := &server{pool: pool, log: log, metrics: newMetrics()}

	// Sefaria client over an instrumented transport: every outbound call is timed,
	// counted (metrics), and logged to api_calls (the sink). base may be overridden
	// for tests/staging via SEFARIA_BASE_URL.
	httpClient := &http.Client{
		Timeout:   30 * time.Second,
		Transport: &instrumentedTransport{base: http.DefaultTransport, m: srv.metrics, sink: srv.recordAPICall},
	}
	srv.sefaria = sefaria.New(
		sefaria.WithHTTPClient(httpClient),
		sefaria.WithBaseURL(os.Getenv("SEFARIA_BASE_URL")),
	)

	go srv.initSchema(ctx) // until this succeeds, /readyz reports 503

	m := srv.metrics
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", srv.healthz)
	mux.HandleFunc("GET /readyz", srv.readyz)
	mux.HandleFunc("GET /", m.instrument("home", srv.home))
	mux.HandleFunc("POST /search", m.instrument("search", srv.handleSearch))
	mux.HandleFunc("GET /items", m.instrument("items", srv.listItems))
	mux.HandleFunc("POST /items", m.instrument("items", srv.createItem))
	mux.Handle("GET /metrics", promhttp.Handler())

	httpSrv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      35 * time.Second, // a search waits on the upstream API
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		log.Info("listening", "addr", httpSrv.Addr)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("http server error", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	log.Info("shutdown signal received; draining")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		log.Error("graceful shutdown failed", "err", err)
	}
}

func (s *server) initSchema(ctx context.Context) {
	backoff := time.Second
	for {
		execCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		_, err := s.pool.Exec(execCtx, schema)
		cancel()
		if err == nil {
			s.ready.Store(true)
			s.log.Info("schema ready")
			return
		}
		s.log.Warn("schema init failed; retrying", "err", err, "backoff", backoff.String())
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
}

// home renders the search page with recent activity loaded from Postgres.
func (s *server) home(w http.ResponseWriter, r *http.Request) {
	data := pageData{Size: 5}
	s.loadRecent(r.Context(), &data)
	s.render(w, data)
}

// handleSearch runs a Sefaria search, persists it + its results, and re-renders
// the page with the results in place.
func (s *server) handleSearch(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		s.renderErr(w, r, "could not parse form")
		return
	}
	query := strings.TrimSpace(r.FormValue("q"))
	size := clamp(atoiDefault(r.FormValue("size"), 5), 1, 25)
	exact := r.FormValue("exact") != ""
	field := sefaria.SearchFieldNaiveLemmatizer
	if exact {
		field = sefaria.SearchFieldExact
	}

	data := pageData{Query: query, Size: size, Exact: exact}
	if query == "" {
		data.ErrMsg = "Enter a search term."
		s.loadRecent(r.Context(), &data)
		s.render(w, data)
		return
	}

	s.metrics.searches.Inc()
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	resp, err := s.sefaria.Search(ctx, sefaria.SearchRequest{Query: query, Field: field, Size: size})
	if err != nil {
		s.log.Warn("sefaria search failed", "query", query, "err", err)
		data.ErrMsg = "Search failed: " + err.Error()
		s.loadRecent(r.Context(), &data)
		s.render(w, data)
		return
	}

	data.Took = resp.Took
	data.HitCount = resp.Hits.Total
	for i, hit := range resp.Hits.Hits {
		data.Results = append(data.Results, resultView{
			Rank: i + 1, Ref: hit.Source.Ref, HeRef: hit.Source.HeRef, Snippet: hit.Snippet(),
		})
	}

	s.persistSearch(string(field), data) // best-effort; logs on error
	s.loadRecent(r.Context(), &data)
	s.render(w, data)
}

// persistSearch writes the search row and its result rows. Best-effort: a write
// failure is logged but never breaks the response. Uses a detached context so it
// completes even if the client disconnected.
func (s *server) persistSearch(field string, d pageData) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var searchID int64
	err := s.pool.QueryRow(ctx,
		`INSERT INTO searches (query, field, size, hit_count, took_ms)
		 VALUES ($1,$2,$3,$4,$5) RETURNING id`,
		d.Query, field, d.Size, d.HitCount, d.Took,
	).Scan(&searchID)
	if err != nil {
		s.log.Error("persist search", "err", err)
		return
	}
	s.metrics.dbRows.WithLabelValues("searches").Inc()

	for _, res := range d.Results {
		if _, err := s.pool.Exec(ctx,
			`INSERT INTO search_results (search_id, rank, ref, he_ref, snippet)
			 VALUES ($1,$2,$3,$4,$5)`,
			searchID, res.Rank, res.Ref, res.HeRef, res.Snippet,
		); err != nil {
			s.log.Error("persist search result", "err", err)
			return
		}
		s.metrics.dbRows.WithLabelValues("search_results").Inc()
	}
}

// recordAPICall is the instrumented-transport sink: it logs one outbound call to
// api_calls. Detached context + best-effort (the metric is already recorded).
func (s *server) recordAPICall(rec callRecord) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO api_calls (method, url, status, duration_ms) VALUES ($1,$2,$3,$4)`,
		rec.method, rec.url, rec.status, rec.duration.Milliseconds(),
	); err != nil {
		s.log.Error("persist api_call", "err", err)
		return
	}
	s.metrics.dbRows.WithLabelValues("api_calls").Inc()
}

// loadRecent fills the two recent-activity panels from Postgres.
func (s *server) loadRecent(ctx context.Context, d *pageData) {
	srows, err := s.pool.Query(ctx,
		`SELECT query, field, hit_count, created_at FROM searches ORDER BY id DESC LIMIT 10`)
	if err == nil {
		defer srows.Close()
		for srows.Next() {
			var v recentView
			if err := srows.Scan(&v.Query, &v.Field, &v.HitCount, &v.CreatedAt); err == nil {
				d.Recent = append(d.Recent, v)
			}
		}
	} else {
		s.log.Warn("load recent searches", "err", err)
	}

	crows, err := s.pool.Query(ctx,
		`SELECT method, url, status, duration_ms, created_at FROM api_calls ORDER BY id DESC LIMIT 10`)
	if err == nil {
		defer crows.Close()
		for crows.Next() {
			var v apiCallView
			if err := crows.Scan(&v.Method, &v.URL, &v.Status, &v.DurationMS, &v.CreatedAt); err == nil {
				d.Calls = append(d.Calls, v)
			}
		}
	} else {
		s.log.Warn("load recent api_calls", "err", err)
	}
}

func (s *server) render(w http.ResponseWriter, d pageData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := homeTmpl.Execute(w, d); err != nil {
		s.log.Error("render template", "err", err)
	}
}

func (s *server) renderErr(w http.ResponseWriter, r *http.Request, msg string) {
	d := pageData{Size: 5, ErrMsg: msg}
	s.loadRecent(r.Context(), &d)
	s.render(w, d)
}

// healthz is liveness: process up and serving; deliberately does NOT touch the DB.
func (s *server) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// readyz is readiness: schema in place and the DB answers a ping.
func (s *server) readyz(w http.ResponseWriter, r *http.Request) {
	if !s.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "initializing"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.pool.Ping(ctx); err != nil {
		s.log.Warn("readiness ping failed", "err", err)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// --- retained JSON items API (original read/write demo) ----------------------

type item struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *server) listItems(w http.ResponseWriter, r *http.Request) {
	rows, err := s.pool.Query(r.Context(), `SELECT id, name, created_at FROM items ORDER BY id`)
	if err != nil {
		s.serverError(w, "query items", err)
		return
	}
	defer rows.Close()
	items := []item{}
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.ID, &it.Name, &it.CreatedAt); err != nil {
			s.serverError(w, "scan item", err)
			return
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		s.serverError(w, "iterate items", err)
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (s *server) createItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name string `json:"name"`
	}
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	if in.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return
	}
	var it item
	err := s.pool.QueryRow(r.Context(),
		`INSERT INTO items (name) VALUES ($1) RETURNING id, name, created_at`, in.Name,
	).Scan(&it.ID, &it.Name, &it.CreatedAt)
	if err != nil {
		s.serverError(w, "insert item", err)
		return
	}
	s.metrics.dbRows.WithLabelValues("items").Inc()
	writeJSON(w, http.StatusCreated, it)
}

func (s *server) serverError(w http.ResponseWriter, ctxMsg string, err error) {
	s.log.Error(ctxMsg, "err", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func atoiDefault(s string, def int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return def
}

func clamp(n, lo, hi int) int {
	if n < lo {
		return lo
	}
	if n > hi {
		return hi
	}
	return n
}
