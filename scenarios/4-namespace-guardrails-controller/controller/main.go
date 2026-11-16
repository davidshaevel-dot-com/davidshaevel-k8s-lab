// Command namespace-guardrails runs the namespace guardrails controller against the
// cluster of your current kube context.
package main

import (
	"flag"
	"os"

	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/davidshaevel-dot-com/davidshaevel-k8s-lab/scenarios/4-namespace-guardrails-controller/controller/internal/controller"
)

func main() {
	logOpts := zap.Options{Development: true}
	logOpts.BindFlags(flag.CommandLine)
	flag.Parse()
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&logOpts)))
	log := ctrl.Log.WithName("setup")

	// GetConfigOrDie reads the kubeconfig the way kubectl does ($KUBECONFIG, else
	// ~/.kube/config) and uses its current context.
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: clientgoscheme.Scheme,
		// A local run needs neither a metrics endpoint nor health probes, and with a
		// single copy running there is no leader to elect. A controller deployed with
		// several replicas would turn leader election on.
		Metrics:                metricsserver.Options{BindAddress: "0"},
		HealthProbeBindAddress: "0",
		LeaderElection:         false,
	})
	if err != nil {
		log.Error(err, "creating the manager")
		os.Exit(1)
	}

	reconciler := &controller.GuardrailsReconciler{Client: mgr.GetClient(), Scheme: mgr.GetScheme()}
	if err := reconciler.SetupWithManager(mgr); err != nil {
		log.Error(err, "registering the reconciler")
		os.Exit(1)
	}

	log.Info("starting the manager; stop it with Ctrl-C")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		log.Error(err, "running the manager")
		os.Exit(1)
	}
}
