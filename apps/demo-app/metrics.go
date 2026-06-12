package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// metrics holds the app-level Prometheus collectors. The default Go/process
// collectors are registered automatically by client_golang.
type metrics struct {
	httpRequests   *prometheus.CounterVec   // by path, method, status
	httpDuration   *prometheus.HistogramVec // by path
	searches       prometheus.Counter       // searches performed
	sefariaCalls   *prometheus.CounterVec   // outbound calls, by status
	sefariaLatency prometheus.Histogram     // outbound call latency
	dbRows         *prometheus.CounterVec   // rows written, by table
}

func newMetrics() *metrics {
	return &metrics{
		httpRequests: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "demoapp_http_requests_total",
			Help: "HTTP requests handled, by path, method and status.",
		}, []string{"path", "method", "status"}),
		httpDuration: promauto.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "demoapp_http_request_duration_seconds",
			Help:    "HTTP request handling latency, by path.",
			Buckets: prometheus.DefBuckets,
		}, []string{"path"}),
		searches: promauto.NewCounter(prometheus.CounterOpts{
			Name: "demoapp_searches_total",
			Help: "Sefaria searches performed via the web UI.",
		}),
		sefariaCalls: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "demoapp_sefaria_requests_total",
			Help: "Outbound Sefaria API calls, by HTTP status (or 'error').",
		}, []string{"status"}),
		sefariaLatency: promauto.NewHistogram(prometheus.HistogramOpts{
			Name:    "demoapp_sefaria_request_duration_seconds",
			Help:    "Outbound Sefaria API call latency.",
			Buckets: []float64{.05, .1, .25, .5, 1, 2.5, 5, 10},
		}),
		dbRows: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "demoapp_db_rows_written_total",
			Help: "Rows written to Postgres, by table.",
		}, []string{"table"}),
	}
}

// instrument wraps a handler to record request count + duration. The route label
// is passed explicitly so high-cardinality paths can't blow up the metric.
func (m *metrics) instrument(route string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		h(sw, r)
		m.httpDuration.WithLabelValues(route).Observe(time.Since(start).Seconds())
		m.httpRequests.WithLabelValues(route, r.Method, strconv.Itoa(sw.status)).Inc()
	}
}

// statusWriter captures the response status for the request metric.
type statusWriter struct {
	http.ResponseWriter
	status int
}

func (s *statusWriter) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// callRecord is one outbound API call, handed to a sink for logging + metrics.
type callRecord struct {
	method   string
	url      string
	status   int // 0 on transport error
	duration time.Duration
	err      error
}

// instrumentedTransport times each outbound request, records a metric, and hands
// the record to a sink (the server persists it to api_calls). It wraps a base
// RoundTripper so it composes with the default transport.
type instrumentedTransport struct {
	base http.RoundTripper
	m    *metrics
	sink func(callRecord)
}

func (t *instrumentedTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	start := time.Now()
	resp, err := t.base.RoundTrip(req)
	rec := callRecord{
		method:   req.Method,
		url:      req.URL.String(),
		duration: time.Since(start),
		err:      err,
	}
	statusLabel := "error"
	if err == nil {
		rec.status = resp.StatusCode
		statusLabel = strconv.Itoa(resp.StatusCode)
	}
	t.m.sefariaLatency.Observe(rec.duration.Seconds())
	t.m.sefariaCalls.WithLabelValues(statusLabel).Inc()
	if t.sink != nil {
		t.sink(rec)
	}
	return resp, err
}
