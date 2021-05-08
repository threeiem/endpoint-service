package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"

	// TODO: retire uber/automaxprocs when the behavior becomes part of Go's stdlib
	// tracking: https://github.com/uber-go/automaxprocs/issues/21#issuecomment-571707692
	// tracking: https://github.com/golang/go/issues/33803
	_ "go.uber.org/automaxprocs"

	"github.com/pantheon-systems/certinel"
	certauth "github.com/pantheon-systems/go-certauth"
	"github.com/pantheon-systems/go-certauth/certutils"
	"github.com/pantheon-systems/go-demo-service/pkg/app"
	"github.com/pantheon-systems/go-demo-service/pkg/appmetrics"
	"github.com/pantheon-systems/go-demo-service/pkg/certwatcher"
	"github.com/pantheon-systems/go-demo-service/pkg/healthz"
	"github.com/pantheon-systems/go-demo-service/pkg/server"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const (
	appName = "go-demo-service"
)

func initConfig() error {
	viper.SetDefault("debug", true)
	viper.SetDefault("port-healthz", 8080)

	viper.SetConfigName(appName)
	viper.AddConfigPath(".")
	viper.AddConfigPath("/configmaps/config")
	viper.SetEnvPrefix(appName) // will be uppercased automatically: https://github.com/spf13/viper/blob/master/README.md#working-with-environment-variables
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))
	viper.AutomaticEnv()
	err := viper.ReadInConfig()
	if err != nil {
		return fmt.Errorf("config read error: %s", err)
	}
	return nil
}

func initLog() {
	log.SetLevel(log.InfoLevel)
	if viper.GetBool("debug") {
		log.SetLevel(log.DebugLevel)
	}
	log.SetOutput(os.Stdout)
	if viper.GetBool("log-fmt-json") {
		log.SetFormatter(&log.JSONFormatter{
			TimestampFormat: "2006-01-02T15:04:05.999Z07:00", // RFC3339 at millisecond precision
			FieldMap: log.FieldMap{
				log.FieldKeyTime: "@timestamp",
			},
		})
		log.Info("Log format set to JSON")
	}
}

func initHTTPServer(certWatcher *certinel.Certinel) (*server.Server, error) {
	caCertPool, err := certutils.LoadCACertFile(viper.GetString("ca-cert"))
	if err != nil {
		return nil, err
	}
	adminAuth := certauth.NewAuth(certauth.Options{
		AllowedOUs: []string{"titan", "monitoring", "engineering"},
	})
	bindingAuth := certauth.NewAuth(certauth.Options{
		AllowedOUs: []string{"titan", "monitoring", "engineering", "site"},
	})
	config := server.Config{
		Port:               viper.GetInt("bind-port"),
		BindAddress:        viper.GetString("bind-address"),
		ServerCert:         viper.GetString("server-cert"),
		ServerKey:          viper.GetString("server-key"),
		CACertPool:         caCertPool,
		AdminAuthHandler:   adminAuth.RouterHandler,
		BindingAuthHandler: bindingAuth.RouterHandler,
		CertWatcher:        certWatcher,
	}
	log.Infof("Starting TLS server: %+v", config)
	return server.New(config), nil
}

func initHealthz(s *server.Server) error {
	config := healthz.Config{
		BindPort: viper.GetInt("port-healthz"),
		BindAddr: viper.GetString("bind-address-healthz"),
		Hostname: viper.GetString("pod-name"),
		Providers: []healthz.ProviderInfo{
			{
				Type:        "App",
				Description: "Check app health.",
				Check:       s.App,
			},
		},
	}
	if config.BindPort < 1 || config.BindPort > 65535 {
		return fmt.Errorf("Invalid port number: %d", config.BindPort)
	}
	log.Infof("Healthz: config loaded: %+v", config)

	healthServer, err := healthz.New(config)
	if err != nil {
		return err
	}
	s.HealthzHandler = healthServer.HandleHealthz
	log.Infof("Healthz loaded: %+v", healthServer)
	go healthServer.StartHealthz()
	return nil
}

func initMetrics() error {
	// Metrics config
	metricsConfig := appmetrics.Config{
		DebugBindPort:  viper.GetInt("port-debug"),
		DebugBindAddr:  "localhost",
		GraphiteHost:   viper.GetString("graphite-host"),
		MetricHostname: viper.GetString("metric-hostname"),
		AppName:        appName,
		FlushInterval:  viper.GetDuration("metric-flush-interval"),
	}
	return appmetrics.Run(metricsConfig)
}

func initCertWatcher() *certinel.Certinel {
	return certwatcher.Start(viper.GetString("server-cert"), viper.GetString("server-key"))
}

func runServer(serverCtx context.Context, a *app.App, certWatcher *certinel.Certinel) {
	// HTTP server
	httpServer, err := initHTTPServer(certWatcher)
	fatalIfErr(err)
	httpServer.App = a

	// Healthz checker
	err = initHealthz(httpServer)
	fatalIfErr(err)

	log.Info("Starting service")
	err = httpServer.ListenAndServe(serverCtx)
	if err != nil {
		log.Error(err)
	}
}

func main() {
	// Logging and configuration
	err := initConfig()
	fatalIfErr(err)

	initLog()

	// Metrics
	err = initMetrics()
	fatalIfErr(err)

	// Application container
	appConfig := app.Config{
		WorkerSleep: viper.GetDuration("worker-sleep"),
		DemoMetrics: viper.GetStringSlice("demo-metrics"),
	}
	a, err := app.New(appConfig)
	fatalIfErr(err)

	workerCtx, workerShutdown := context.WithCancel(context.Background())
	serverCtx, serverShutdown := context.WithCancel(context.Background())
	workerWg := &sync.WaitGroup{}

	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		for sig := range c {
			log.Warnf("Caught signal: %+v, attempting clean shutdown", sig)
			// Shut down the workers first, so we can continue to handle requests while they finish.
			workerShutdown()
			workerWg.Wait()

			serverShutdown()

			os.Exit(0)
		}
	}()

	log.Info("Running workers")
	a.RunWorkers(workerCtx, workerWg)

	certWatcher := initCertWatcher()
	runServer(serverCtx, a, certWatcher)
}

func fatalIfErr(err error) {
	if err != nil {
		log.WithError(err).Fatal("Startup failure")
	}
}
