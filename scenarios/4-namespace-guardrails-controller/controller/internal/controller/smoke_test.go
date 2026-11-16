package controller

// Smoke tests: they check the scaffold and the harness, not the controller's
// behaviour, and they pass before any reconcile logic exists. Run them with
// `make test-smoke`.

import (
	"context"
	"testing"

	"github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/discovery"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// envtestKubernetesMinor is the Kubernetes minor version of the pinned envtest
// binaries (ENVTEST_K8S_VERSION in the Makefile).
const envtestKubernetesMinor = "36"

func TestSmokeAPIServerAnswers(t *testing.T) {
	g := gomega.NewWithT(t)

	dc, err := discovery.NewDiscoveryClientForConfig(cfg)
	g.Expect(err).NotTo(gomega.HaveOccurred())
	version, err := dc.ServerVersion()
	g.Expect(err).NotTo(gomega.HaveOccurred(), "the envtest API server should answer")

	g.Expect(version.Major).To(gomega.Equal("1"))
	g.Expect(version.Minor).To(gomega.Equal(envtestKubernetesMinor),
		"the API server should be the pinned envtest version, got %s", version.GitVersion)
}

func TestSmokeManagerIsRunning(t *testing.T) {
	g := gomega.NewWithT(t)

	// The manager's client reads from the manager's cache, which only fills once the
	// manager has started and its namespace watch is running.
	eventually(g, func(g gomega.Gomega) {
		ns := &corev1.Namespace{}
		g.Expect(managerClient.Get(context.Background(),
			client.ObjectKey{Name: preexistingNamespace}, ns)).To(gomega.Succeed())
	}, "the manager's cache should hold namespace %s", preexistingNamespace)
}

func TestSmokeNamespaceCanBeCreated(t *testing.T) {
	g := gomega.NewWithT(t)

	name := newTestNamespace(t)

	ns := &corev1.Namespace{}
	g.Expect(k8sClient.Get(context.Background(), client.ObjectKey{Name: name}, ns)).
		To(gomega.Succeed(), "namespace %s should exist", name)
	g.Expect(ns.Status.Phase).To(gomega.Equal(corev1.NamespaceActive))
}
