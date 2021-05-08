package server

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"fmt"
	stdLibLog "log"
	"net/http"
	"time"

	"github.com/julienschmidt/httprouter"
	"github.com/pantheon-systems/certinel"
	"github.com/pantheon-systems/go-certauth/certutils"
	"github.com/pantheon-systems/go-demo-service/pkg/app"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
)

var log = logrus.WithField("component", "server")

const (
	// MaxHeaderBytes controls the maximum number of bytes the
	// server will read parsing the request header's keys and
	// values, including the request line. It does not limit the
	// size of the request body.
	MaxHeaderBytes = 1 << 20
)

// HandlerWrapper type allows us to bypass the clientauth in unit testing.
type HandlerWrapper func(h httprouter.Handle) httprouter.Handle

type Config struct {
	App              *app.App
	Port             int
	BindAddress      string
	ServerCert       string
	ServerKey        string
	CACertPool       *x509.CertPool
	GetStatusTimeout time.Duration

	AdminAuthHandler   HandlerWrapper
	BindingAuthHandler HandlerWrapper
	CertWatcher        *certinel.Certinel // hot reloads mTLS certificates.
}

type Server struct {
	App              *app.App
	TLSServer        *http.Server
	ServerCert       string
	ServerKey        string
	GetStatusTimeout time.Duration
	HealthzHandler   func(http.ResponseWriter, *http.Request)

	certWatcher *certinel.Certinel
}

// ResponseBody defines how the site/zone failover response looks like.
type ResponseBody struct {
	Message    string `json:"message,omitempty"`
	DebugTrace string `json:"debug_trace,omitempty"`
}

// New server constructor.
func New(config Config) *Server {
	s := &Server{
		ServerCert:       config.ServerCert,
		ServerKey:        config.ServerKey,
		App:              config.App,
		GetStatusTimeout: config.GetStatusTimeout,
		certWatcher:      config.CertWatcher,
	}
	tlsConfig := certutils.TLSServerConfig{
		CertPool:    config.CACertPool,
		BindAddress: config.BindAddress,
		Port:        config.Port,
		Router:      s.GetRouter(config.AdminAuthHandler, config.BindingAuthHandler),
	}
	server := certutils.NewTLSServer(tlsConfig)
	server.MaxHeaderBytes = MaxHeaderBytes
	server.ReadHeaderTimeout = 5 * time.Second
	server.ReadTimeout = 5 * time.Second
	server.WriteTimeout = 60 * time.Second
	server.IdleTimeout = 120 * time.Second
	server.TLSConfig.GetCertificate = s.certWatcher.GetCertificate
	s.TLSServer = server
	return s
}

// GetRouter defines the API routes.
func (s *Server) GetRouter(adminAuthWrapper HandlerWrapper, bindingAuthWrapper HandlerWrapper) http.Handler {
	router := httprouter.New()
	router.NotFound = http.HandlerFunc(NotFound)

	// The following API endpoints require privileged access
	router.GET("/v1/demo-get", adminAuthWrapper(s.DemoFunc))
	router.POST("/v1/demo-post", adminAuthWrapper(s.DemoFunc))

	// Site bindings can access these API endpoints
	router.GET("/v1/demo-less-priviledge", bindingAuthWrapper(s.DemoFunc))

	return router
}

// ListenAndServe starts the server.
func (s *Server) ListenAndServe(ctx context.Context) error {
	if s.HealthzHandler == nil {
		return errors.New("server.HealthzHandler == nil, please add a handler")
	}
	w := log.Logger.Writer()
	s.TLSServer.ErrorLog = stdLibLog.New(w, "", 0)

	go func() {
		err := s.TLSServer.ListenAndServeTLS("", "")
		if err != nil && err != http.ErrServerClosed {
			log.WithError(err).Errorf("error from tls server")
			panic(err.Error())
		}
		log.Info("ListenAndServeTLS stopped")
	}()

	// Block waiting for the shutdown signal.
	<-ctx.Done()
	log.Info("Shutting down server")
	tlsCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	err := s.TLSServer.Shutdown(tlsCtx)
	s.certWatcher.Close()
	log.Info("Server stopped")
	return err
}

// DemoFunc handles GET /v1/sites/:site_id and retrieves a site.
func (s *Server) DemoFunc(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	var log = log.WithField("func", "DemoFunc")
	enc := json.NewEncoder(w)
	response := struct {
		Message string
	}{
		Message: "Hello World!",
	}
	log.Infoln("Hello World!")
	err := enc.Encode(response)
	if err != nil {
		log.Errorln(err)
	}
}

// NotFound returns the default response for when routes are not found.
func NotFound(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusNotFound)
	fmt.Fprint(w, "The requested route does not exist.\n")
}

// HealthzProxyHandler is the handler for /v1/healthz
func (s *Server) HealthzProxyHandler(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// We don't want to expose the non-TLS healthz endpoint on the internet, so
	// this just wraps the function.
	s.HealthzHandler(w, r)
}
