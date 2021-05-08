package healthz

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/pkg/errors"
)

var config Config

func init() {
	config = Config{
		BindPort: 80,
		BindAddr: "localhost",
		Hostname: "tester",
	}
}

func TestHappy(t *testing.T) {
	config.Providers = []ProviderInfo{
		ProviderInfo{
			Check: &Happy{},
		},
	}
	hz, err := New(config)
	if err != nil {
		t.Fatal(err.Error())
	}
	req, err := http.NewRequest("GET", "/healthz", nil)
	if err != nil {
		t.Fatal(err.Error())
	}
	w := httptest.NewRecorder()
	hz.Server.Handler.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatal("Expected 200 OK, got:", w.Code)
	}
	if w.Body.String() != `{"Errors":null,"Hostname":"tester"}`+"\n" {
		t.Fatal("Unexpected JSON body, got:", w.Body.String())
	}
}

func TestNotFound(t *testing.T) {
	config.Providers = []ProviderInfo{
		ProviderInfo{
			Check: &Happy{},
		},
	}
	hz, err := New(config)
	if err != nil {
		t.Fatal(err.Error())
	}
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err.Error())
	}
	w := httptest.NewRecorder()
	hz.Server.Handler.ServeHTTP(w, req)
	if w.Code != 404 {
		t.Fatal("Expected 404 Not Found, got:", w.Code)
	}
}

func TestUnhappy(t *testing.T) {
	config.Providers = []ProviderInfo{
		ProviderInfo{
			Check:       &Unhappy{},
			Type:        "DBConn",
			Description: "Ensure the database connection is up",
		},
	}
	hz, err := New(config)
	if err != nil {
		t.Fatal(err.Error())
	}
	req, err := http.NewRequest("GET", "/healthz", nil)
	if err != nil {
		t.Fatal(err.Error())
	}
	w := httptest.NewRecorder()
	hz.Server.Handler.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatal("Expected 200 OK, got:", w.Code)
	}
	if w.Body.String() != `{"Errors":[{"Type":"DBConn","ErrMsg":"failed","Description":"Ensure the database connection is up"}],"Hostname":"tester"}`+"\n" {
		t.Fatal("Unexpected JSON body, got:", w.Body.String())
	}
}

func TestMultipleOneUnhappy(t *testing.T) {
	config.Providers = []ProviderInfo{
		ProviderInfo{
			Check:       &Unhappy{},
			Type:        "DBConn",
			Description: "Ensure the database connection is up",
		},
		ProviderInfo{
			Check:       &Happy{},
			Type:        "Foo",
			Description: "Ensure we can reach Foo",
		},
		ProviderInfo{
			Check:       &Happy{},
			Type:        "Metric",
			Description: "Watch a key metric for failure",
		},
	}
	hz, err := New(config)
	if err != nil {
		t.Fatal(err.Error())
	}
	req, err := http.NewRequest("GET", "/healthz", nil)
	if err != nil {
		t.Fatal(err.Error())
	}
	w := httptest.NewRecorder()
	hz.Server.Handler.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatal("Expected 200 OK, got:", w.Code)
	}
	if w.Body.String() != `{"Errors":[{"Type":"DBConn","ErrMsg":"failed","Description":"Ensure the database connection is up"}],"Hostname":"tester"}`+"\n" {
		t.Fatal("Unexpected JSON body, got:", w.Body.String())
	}
}

type Happy struct{}

func (hz *Happy) HealthZ() error {
	return nil
}

type Unhappy struct{}

func (hz *Unhappy) HealthZ() error {
	return errors.New("failed")
}
