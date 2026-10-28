package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
)

func newTestHandler(t *testing.T) (*server, http.Handler) {
	t.Helper()
	registry := prometheus.NewRegistry()
	s := newServer("test", "pod-1", registry)
	return s, s.routes(registry)
}

func get(handler http.Handler, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestRootDescribesInstance(t *testing.T) {
	_, handler := newTestHandler(t)

	rec := get(handler, "/")

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	want := map[string]string{"service": "hello", "version": version, "environment": "test", "hostname": "pod-1"}
	for key, value := range want {
		if body[key] != value {
			t.Errorf("%s = %q, want %q", key, body[key], value)
		}
	}
}

func TestUnknownPathIsNotFound(t *testing.T) {
	_, handler := newTestHandler(t)

	if code := get(handler, "/nope").Code; code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", code, http.StatusNotFound)
	}
}

func TestReadinessFollowsServerState(t *testing.T) {
	s, handler := newTestHandler(t)

	if code := get(handler, "/readyz").Code; code != http.StatusServiceUnavailable {
		t.Fatalf("before start: status = %d, want %d", code, http.StatusServiceUnavailable)
	}
	s.ready.Store(true)
	if code := get(handler, "/readyz").Code; code != http.StatusOK {
		t.Fatalf("after start: status = %d, want %d", code, http.StatusOK)
	}
}

func TestLivenessDoesNotDependOnReadiness(t *testing.T) {
	_, handler := newTestHandler(t)

	if code := get(handler, "/healthz").Code; code != http.StatusOK {
		t.Fatalf("status = %d, want %d", code, http.StatusOK)
	}
}

func TestMetricsCountRequestsByStatus(t *testing.T) {
	_, handler := newTestHandler(t)
	get(handler, "/")
	get(handler, "/readyz")

	body := get(handler, "/metrics").Body.String()

	for _, line := range []string{
		`hello_http_requests_total{code="200",path="/"} 1`,
		`hello_http_requests_total{code="503",path="/readyz"} 1`,
	} {
		if !strings.Contains(body, line) {
			t.Errorf("metrics missing %q", line)
		}
	}
}
