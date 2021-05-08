package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/julienschmidt/httprouter"
)

func TestGetDemoPath(t *testing.T) {
	serverConfig := Config{
		AdminAuthHandler:   mockRouterHandler,
		BindingAuthHandler: mockRouterHandler,
	}
	server := New(serverConfig)
	router := server.GetRouter(mockRouterHandler, mockRouterHandler)

	r, _ := http.NewRequest("GET", "/v1/demo-get", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200 response code, got: %d %s", w.Code, w.Body)
	}
	expectedBody := "hello world"
	receivedBody := strings.ToLower(strings.TrimSpace(w.Body.String()))
	if !strings.Contains(receivedBody, expectedBody) {
		t.Fatalf("expected body '%s', got: '%s'", expectedBody, receivedBody)
	}
}

func mockRouterHandler(h httprouter.Handle) httprouter.Handle {
	return httprouter.Handle(func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		// Always allow the request for testing purposes.
		h(w, r, ps)
	})
}
