package app

import (
	"context"
	"runtime"
	"runtime/debug"
	"time"
)

// MonitorWorker runs the monitoring goroutine that performs cleanup and
// periodic tasks alongside the main processing.
func (a *App) DemoWorker(ctx context.Context) error {
	log := log.WithField("worker", "demo")
	defer func() {
		log.Info("shut down")
		if err := recover(); err != nil {
			stack := string(debug.Stack())
			//stats.panicCount.Inc(1)
			b := make([]byte, 1024*8)
			runtime.Stack(b, false)
			log.WithField("severity", "critical").WithField("stack", stack).Error("runtime panic: ", err)
			// TODO: send panics to slack when running in production.
			//go s.SlackMessenger.SendCritical(fmt.Sprintf("Application panic: %s", err))
			//stats.panicCount.Inc(1)
		}
	}()

	iterCount := 0
	// It takes a.MonitorWorkerSleep until the first worker runs.
	// We don't want health checks to fail while we wait for this first run.
	log.Infof("Running worker, iter: %d", iterCount)
	a.MonitorWorkerTasks()

	for {
		select {
		case <-time.After(a.WorkerSleep):
			iterCount++
			log.Infof("Running demo worker, iter: %d", iterCount)
			a.MonitorWorkerTasks()
		case <-ctx.Done():
			log.Info("DemoWorker received shutdown signal")
			return nil
		}
	}
}

func (a *App) MonitorWorkerTasks() {
	a.DemoTask()
}

func (a *App) DemoTask() {
	// Always check last minute.
	// TODO: figure out if we want to make this configurable.
	log.Infoln("Running demo task")
}
