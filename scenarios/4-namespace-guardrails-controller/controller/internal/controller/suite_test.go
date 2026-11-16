package controller

// The test suite's harness: TestMain starts a local API server and etcd with envtest,
// starts a controller manager with the guardrails reconciler registered, runs the
// tests, and stops everything again. The smoke tests (smoke_test.go) and the contract
// tests (contract_test.go, build tag "contract") share it.
//
// envtest runs kube-apiserver and etcd only: no kube-controller-manager, no scheduler,
// no kubelet. Two consequences show up in these tests:
//   - A deleted namespace stays in Terminating forever, because the namespace
//     controller that would empty and remove it is not running. Every test therefore
//     gets a namespace with a fresh, generated name.
//   - Garbage collection does not run, so deleting an owner does not delete what it
//     owns.

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/onsi/gomega"
	"github.com/onsi/gomega/format"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
)

const (
	// testNamespacePrefix starts the name of every namespace the tests create. The
	// controller must not skip namespaces with this prefix (see the contract).
	testNamespacePrefix = "guardrails-test-"

	// preexistingNamespace is created before the manager starts, so a test can check
	// what the controller does with namespaces that were already there.
	preexistingNamespace = testNamespacePrefix + "preexisting"

	// How long the tests wait for the cluster to reach a state, how often they look,
	// and how long a state must hold to count as settled.
	eventuallyTimeout = 10 * time.Second
	pollInterval      = 250 * time.Millisecond
	settleDuration    = 3 * time.Second
)

var (
	// cfg reaches the envtest API server.
	cfg *rest.Config

	// k8sClient talks to the API server directly, with no cache, so a test always
	// sees the cluster's current state. Tests use it to set up and to check.
	k8sClient client.Client

	// managerClient is the manager's own client. Its reads come from the manager's
	// cache; the smoke tests use it to show that the manager is running.
	managerClient client.Client
)

func TestMain(m *testing.M) {
	os.Exit(runSuite(m))
}

// runSuite starts envtest and the manager, runs the tests and returns their exit code.
// It is a separate function so that its deferred cleanups run before os.Exit.
func runSuite(m *testing.M) int {
	ctrl.SetLogger(zap.New(zap.WriteTo(os.Stderr), zap.UseDevMode(true)))

	// When an assertion fails on an API error, print the error's message only, not the
	// whole Go struct behind it (Gomega prints the message first in any case).
	format.RegisterCustomFormatter(func(value any) (string, bool) {
		if _, isError := value.(error); isError {
			return "", true
		}
		return "", false
	})

	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		fmt.Fprintln(os.Stderr, "KUBEBUILDER_ASSETS is not set. Run the tests with "+
			"`make test-smoke` or `make test-contract`: they download the pinned envtest "+
			"binaries and point KUBEBUILDER_ASSETS at them.")
		return 1
	}

	testEnv := &envtest.Environment{}
	var err error
	cfg, err = testEnv.Start()
	if err != nil {
		fmt.Fprintf(os.Stderr, "starting envtest: %v\n", err)
		return 1
	}
	defer func() {
		if err := testEnv.Stop(); err != nil {
			fmt.Fprintf(os.Stderr, "stopping envtest: %v\n", err)
		}
	}()

	k8sClient, err = client.New(cfg, client.Options{Scheme: clientgoscheme.Scheme})
	if err != nil {
		fmt.Fprintf(os.Stderr, "creating the test client: %v\n", err)
		return 1
	}

	ctx := context.Background()
	preexisting := &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: preexistingNamespace}}
	if err := k8sClient.Create(ctx, preexisting); err != nil {
		fmt.Fprintf(os.Stderr, "creating namespace %s: %v\n", preexistingNamespace, err)
		return 1
	}

	mgr, err := ctrl.NewManager(cfg, ctrl.Options{
		Scheme:                 clientgoscheme.Scheme,
		Metrics:                metricsserver.Options{BindAddress: "0"},
		HealthProbeBindAddress: "0",
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "creating the manager: %v\n", err)
		return 1
	}
	reconciler := &GuardrailsReconciler{Client: mgr.GetClient(), Scheme: mgr.GetScheme()}
	if err := reconciler.SetupWithManager(mgr); err != nil {
		fmt.Fprintf(os.Stderr, "registering the reconciler: %v\n", err)
		return 1
	}
	managerClient = mgr.GetClient()

	mgrCtx, stopManager := context.WithCancel(ctx)
	mgrDone := make(chan error, 1)
	go func() { mgrDone <- mgr.Start(mgrCtx) }()
	defer func() {
		stopManager()
		if err := <-mgrDone; err != nil {
			fmt.Fprintf(os.Stderr, "manager stopped with an error: %v\n", err)
		}
	}()

	syncCtx, cancelSync := context.WithTimeout(ctx, 30*time.Second)
	defer cancelSync()
	if !mgr.GetCache().WaitForCacheSync(syncCtx) {
		fmt.Fprintln(os.Stderr, "the manager's cache did not sync within 30s")
		return 1
	}

	return m.Run()
}

// newTestNamespace creates a namespace with a generated name that starts with
// testNamespacePrefix, and returns the name. The namespace is deleted when the test
// ends (under envtest it then stays in Terminating; see the top of this file).
func newTestNamespace(t *testing.T) string {
	t.Helper()
	ns := &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{GenerateName: testNamespacePrefix}}
	if err := k8sClient.Create(context.Background(), ns); err != nil {
		t.Fatalf("creating a test namespace: %v", err)
	}
	t.Cleanup(func() {
		if err := k8sClient.Delete(context.Background(), ns); err != nil {
			t.Logf("deleting namespace %s: %v", ns.Name, err)
		}
	})
	return ns.Name
}

// eventually polls fn until every assertion in it passes or eventuallyTimeout runs
// out. description says, in the failure message, what the test was waiting for.
func eventually(t *testing.T, fn func(g gomega.Gomega), description string, args ...any) {
	t.Helper()
	gomega.NewWithT(t).Eventually(fn).
		WithTimeout(eventuallyTimeout).
		WithPolling(pollInterval).
		Should(gomega.Succeed(), append([]any{description}, args...)...)
}

// consistently checks that every assertion in fn keeps passing for settleDuration.
func consistently(t *testing.T, fn func(g gomega.Gomega), description string, args ...any) {
	t.Helper()
	gomega.NewWithT(t).Consistently(fn).
		WithTimeout(settleDuration).
		WithPolling(pollInterval).
		Should(gomega.Succeed(), append([]any{description}, args...)...)
}
