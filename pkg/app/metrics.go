package app

import (
	"fmt"

	metrics "github.com/rcrowley/go-metrics"
)

// DemoCounter records the number of sites down by zone, as observed by Fastly.
type DemoCounter map[string]metrics.Gauge

type demoMetrics struct {
	demoCounter DemoCounter
}

// TODO: stats is unused. Is there a reason to leave it in place for the demo app?
//nolint:unused
var stats *demoMetrics

func initDemoMetrics(demoMetrics []string) DemoCounter {
	// telemetry.go-demo-service.demo_metrics.(metric-(a,b,c,f)).(demo_number)
	log.Infof("Registering demo stats: %s", demoMetrics)
	gauge := make(DemoCounter, len(demoMetrics))
	for _, demoMetric := range demoMetrics {
		log.Infof("Registering site downtime metrics for zone: %s", demoMetric)
		gauge[demoMetric] = metrics.GetOrRegisterGauge(fmt.Sprintf("demo_metrics.%s.", demoMetric), metrics.DefaultRegistry)
	}
	return gauge
}
