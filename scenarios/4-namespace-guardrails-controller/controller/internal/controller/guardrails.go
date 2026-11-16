// Package controller holds the namespace guardrails controller.
package controller

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// GuardrailsReconciler keeps two guardrail objects in every namespace: a default-deny
// NetworkPolicy and a ResourceQuota.
type GuardrailsReconciler struct {
	// Client reads from the manager's cache and writes to the API server.
	client.Client

	// Scheme maps Go types to Kubernetes kinds. You need it if you set owner
	// references; otherwise it is unused.
	Scheme *runtime.Scheme
}

// Reconcile brings one namespace to the state the contract below describes. The
// manager calls it with the namespace's name in req.Name (req.Namespace is empty,
// because a Namespace is cluster-scoped) whenever something it watches changes, and
// once for every existing namespace when it starts.
//
// # The contract
//
// What it watches
//   - Namespaces. Wired in SetupWithManager below.
//   - The two guardrail objects, so that a change to either one, its deletion
//     included, leads back to a Reconcile of its namespace. Not wired yet: yours.
//
// What it ensures, in every namespace it does not skip (including the namespaces
// that existed before the controller started)
//   - A NetworkPolicy named "default-deny" that selects every pod in the namespace
//     (an empty podSelector), lists both policy types, Ingress and Egress, and has no
//     ingress or egress rules: nothing in and nothing out, unless another policy
//     allows it.
//   - A ResourceQuota named "default-quota" whose spec.hard is exactly:
//     pods 50, services 20, persistentvolumeclaims 10, configmaps 50, secrets 50.
//
// When a guardrail is deleted by hand
//   - It comes back: a new object with the same name and spec.
//
// When a guardrail is edited by hand (OPTIONAL: an extension, not a requirement)
//   - The core contract requires nothing for a hand-edited guardrail. As an optional
//     extension, the controller puts its spec back to the contract's. Its tests are
//     a separate group (make test-contract-optional); do the core contract first.
//   - A question to think about before you start: the API server fills in fields
//     you did not send (defaults), so the object you read back is not the object
//     you wrote. How does your code tell "edited by hand" from "defaulted"?
//
// When an object with a guardrail's name already exists and this controller did not
// create it
//   - Your decision: take it over, leave it alone, or report it. The lab's own
//     namespace "lab" is such a case: it already carries a NetworkPolicy named
//     "default-deny" and a ResourceQuota named "lab-quota". Write down what the
//     controller does and why, and add a test for it.
//
// Which namespaces it skips
//   - Your decision. Some namespaces belong to the cluster itself (kube-system,
//     kube-public, kube-node-lease, and on a managed cluster, the provider's own).
//     A default-deny policy there can cut pods off from DNS and from the API server.
//     Choose the rule, write down why, and add a test for it.
//   - Whatever the rule, it must not skip namespaces whose names start with
//     "guardrails-test-": the contract tests create those.
//   - A namespace that is being deleted gets nothing new: the API server refuses new
//     objects in it, and that refusal is not a failure to retry.
//
// Idempotency
//   - Reconcile may run any number of times for the same namespace. Running it again
//     on a namespace that is already correct changes nothing: no new objects, no
//     updates (their resourceVersion stays the same).
//
// What it returns, and when it requeues
//   - ctrl.Result{} and a nil error when the namespace is as the contract wants it,
//     when the namespace no longer exists, and when it is being deleted. The watches
//     bring the namespace back when something changes; no timed requeue is needed.
//   - A non-nil error when a call to the API server fails in a way that may succeed
//     later (a conflict, a timeout). The manager retries with backoff. A Result set
//     alongside a non-nil error is ignored.
//
// RBAC the logic will need, cluster-wide (a ClusterRole, once the controller runs in
// a cluster; `make run` uses the permissions of your own kube context)
//   - namespaces: get, list, watch
//   - networkpolicies (API group networking.k8s.io): get, list, watch, create, update,
//     patch; delete only if your logic deletes
//   - resourcequotas (core API group): get, list, watch, create, update, patch;
//     delete only if your logic deletes
//   - events: create, patch; only if you record events
func (r *GuardrailsReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	// Yours to write: see the contract above and ../../../exercise.md.
	return ctrl.Result{}, nil
}

// SetupWithManager registers the reconciler with the manager.
//
// The scaffold watches namespaces only, so Reconcile runs for every namespace that
// exists or appears. That is enough to create a guardrail. It is not enough to bring
// a deleted guardrail back, because nothing tells the controller yet that a
// NetworkPolicy or a ResourceQuota changed. Adding those watches is part of the
// exercise: see "Watches and ownership" in ../../../walkthrough.md.
func (r *GuardrailsReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Namespace{}).
		Named("namespace-guardrails").
		Complete(r)
}
