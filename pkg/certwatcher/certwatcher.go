package certwatcher

import (
	"time"

	"github.com/pantheon-systems/certinel"
	"github.com/pantheon-systems/certinel/pollwatcher"
	"github.com/sirupsen/logrus"
)

var log = logrus.WithField("component", "certwatcher")

// certPollInterval defines how often the server and key are polled to see if they were updated.
const certPollInterval = 60 * time.Second

// Start instantiates pollwatcher & certinel and launches the monitoring of the
// certificate and key. Returns the Certinel object.
func Start(cert, key string) *certinel.Certinel {
	// Setup certinel to watch for cert changes
	watcher := pollwatcher.New(cert, key, certPollInterval)
	c := certinel.New(watcher, log, func(err error) {
		log.Fatalf("error: certinel was unable to reload the certificate (key: %s, cert: %s). err='%s'", key, cert, err)
	})
	c.Watch()
	return c
}
