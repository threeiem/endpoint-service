package app

import (
	"context"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
)

var log = logrus.WithField("component", "app")

type WorkerFunc func(context.Context) error

type Config struct {
	WorkerSleep time.Duration
	DemoMetrics []string
}

type App struct {
	WorkerSleep time.Duration
}

func New(config Config) (*App, error) {
	a := &App{
		WorkerSleep: config.WorkerSleep,
	}
	// Registering zones for metrics charts (stats is a package level variable).
	stats = &demoMetrics{
		demoCounter: initDemoMetrics(config.DemoMetrics),
	}
	return a, nil
}

// RunWorkers runs application workers in goroutines
func (a *App) RunWorkers(ctx context.Context, wg *sync.WaitGroup) {
	go a.RunWorker(ctx, wg, "DemoWorker", a.DemoWorker)
}

// RunWorker executes the worker function fn indefinitely. The func
// should handle its own panics. This allows us to restart a crashing
// worker, and if it is unable to come back up, will not cause a memory
// leak when it gets stuck in a crash loop.
func (a *App) RunWorker(ctx context.Context, wg *sync.WaitGroup, name string, fn WorkerFunc) {
	wg.Add(1)
	defer wg.Done()

	for {
		select {
		default:
			log.Infof("RunWorker function: %s", name)
			err := fn(ctx)
			if err != nil {
				log.Error(err)
			}
		case <-ctx.Done():
			log.Infof("closing RunWorker loop: %s", name)
			return
		}
	}
}
