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
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var version = "dev"

const (
	readHeaderTimeout = 5 * time.Second
	drainDelay        = 5 * time.Second
	shutdownTimeout   = 15 * time.Second
)

type server struct {
	environment string
	hostname    string
	ready       atomic.Bool
	requests    *prometheus.CounterVec
	duration    *prometheus.HistogramVec
}

func newServer(environment, hostname string, registry prometheus.Registerer) *server {
	s := &server{
		environment: environment,
		hostname:    hostname,
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "hello_http_requests_total",
			Help: "HTTP requests by path and status code.",
		}, []string{"path", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "hello_http_request_duration_seconds",
			Help:    "HTTP request latency by path.",
			Buckets: prometheus.DefBuckets,
		}, []string{"path"}),
	}
	registry.MustRegister(s.requests, s.duration)
	return s
}

func (s *server) routes(gatherer prometheus.Gatherer) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", s.instrument("/", s.handleRoot))
	mux.HandleFunc("GET /healthz", s.instrument("/healthz", handleHealthz))
	mux.HandleFunc("GET /readyz", s.instrument("/readyz", s.handleReadyz))
	mux.Handle("GET /metrics", promhttp.HandlerFor(gatherer, promhttp.HandlerOpts{}))
	return mux
}

func (s *server) handleRoot(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	err := json.NewEncoder(w).Encode(map[string]string{
		"service":     "hello",
		"version":     version,
		"environment": s.environment,
		"hostname":    s.hostname,
	})
	if err != nil {
		slog.Debug("write response", "error", err)
	}
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func (s *server) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !s.ready.Load() {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.code = code
	r.ResponseWriter.WriteHeader(code)
}

func (s *server) instrument(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		next(rec, r)
		s.duration.WithLabelValues(path).Observe(time.Since(start).Seconds())
		s.requests.WithLabelValues(path, strconv.Itoa(rec.code)).Inc()
	}
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)
	hostname, _ := os.Hostname()
	port := envOr("PORT", "8080")

	registry := prometheus.NewRegistry()
	registry.MustRegister(collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
	s := newServer(envOr("ENVIRONMENT", "local"), hostname, registry)

	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           s.routes(registry),
		ReadHeaderTimeout: readHeaderTimeout,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("listening", "port", port, "version", version)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()
	s.ready.Store(true)

	<-ctx.Done()
	s.ready.Store(false)
	logger.Info("draining before shutdown", "delay", drainDelay)
	time.Sleep(drainDelay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown failed", "error", err)
		os.Exit(1)
	}
	logger.Info("stopped")
}

func envOr(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}
