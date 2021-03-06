package appmetrics

import (
	"fmt"
	"os"
	"time"

	"github.com/sirupsen/logrus"

	graphite "github.com/pantheon-systems/go-metrics-graphite"
	metrics "github.com/rcrowley/go-metrics"
	"github.com/rcrowley/go-metrics/exp"
)

var log = logrus.WithField("component", "appmetrics")

// MethodMetrics holds the metrics we collect on any func/method making requests.
type MethodMetrics struct {
	Success metrics.Counter
	Fail    metrics.Counter
	Timer   metrics.Timer
}

// NewMethodMetrics returns a pointer to a MethodMetrics using the given name.
func NewMethodMetrics(name string) *MethodMetrics {
	return &MethodMetrics{
		Success: metrics.GetOrRegister(name+".success", makeCounterFunc).(metrics.Counter),
		Fail:    metrics.GetOrRegister(name+".failed", makeCounterFunc).(metrics.Counter),
		Timer:   metrics.GetOrRegister(name+".timer", makeTimerFunc).(metrics.Timer),
	}
}

// ServerMetrics holds the metrics we collect inside a server handler.
type ServerMetrics struct {
	Sessions      metrics.Counter
	FailedSession metrics.Counter
	ConnectedTime metrics.Timer
}

type Config struct {
	DebugBindPort  int
	DebugBindAddr  string
	GraphiteHost   string
	MetricHostname string
	AppName        string
	FlushInterval  time.Duration
}

var makeTimerFunc = func() interface{} { return metrics.NewTimer() }
var makeCounterFunc = func() interface{} { return metrics.NewCounter() }

// Run starts the goroutines and servers that handle metrics.
func Run(config Config) error {
	log.Debugf("Setup metrics with config: %+v", config)
	reg := metrics.DefaultRegistry

	// MetricHostname is used in the prefix to differentiate metrics by host.
	if config.MetricHostname == "" {
		host, err := os.Hostname()
		if err != nil {
			return fmt.Errorf("could not detect hostname: %s", err.Error())
		}
		log.Info("autodetected hostname as: ", host)
		config.MetricHostname = host
	}

	// Metrics, expvars and stats will be available for debugging at /debug/metrics, e.g.
	// `http://localhost:6060/debug/metrics`
	go exp.Exp(reg)
	/*go func() {
		profileAddr := fmt.Sprintf(config.DebugBindAddr+":%d", config.DebugBindPort)
		log.Info("starting metrics debug server")
		log.Info(http.ListenAndServe(profileAddr, nil))
	}()*/

	// Run the metric collector
	if config.GraphiteHost != "" {
		metricPrefix := fmt.Sprintf("telemetry.%s", config.AppName)
		log.Infof("using graphite prefix: %s, graphite host: %s", metricPrefix, config.GraphiteHost)
		go graphite.Graphite(reg, config.FlushInterval, metricPrefix, config.GraphiteHost)
	} else {
		log.Warn("no Graphite server specified, not sending metrics")
	}

	return nil
}
