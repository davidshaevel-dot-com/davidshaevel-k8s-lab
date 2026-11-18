//go:build contract

package controller

// Core contract tests: each one encodes one line of the contract written above
// Reconcile in guardrails.go. They fail until the reconcile logic exists, and they go
// green as you write it; when all of them pass, the scenario is done. Run them with
// `make test-contract`; a build without the tag "contract" leaves them out.
// The optional extension has its own group: contract_optional_test.go.
//
// Add new contract tests to this file, with names that start with TestContract:
// `make test-contract` runs only that prefix, and the helpers below exist only under
// the "contract" tag.
//
// They check only what can be seen in the cluster: which objects exist, with what
// spec, and whether they keep changing. They do not care how the controller gets
// there (owner references, labels, create-or-update or apply are all yours to pick).
//
// The expected values below are assertion fixtures: what a test compares the cluster
// against. They mirror the contract, so if you change the contract, change them too.

import (
	"context"
	"testing"
	"time"

	"github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	guardrailPolicyName = "default-deny"
	guardrailQuotaName  = "default-quota"
)

// expectedQuotaHard is the contract's spec.hard for the ResourceQuota.
var expectedQuotaHard = map[corev1.ResourceName]string{
	corev1.ResourcePods:                   "50",
	corev1.ResourceServices:               "20",
	corev1.ResourcePersistentVolumeClaims: "10",
	corev1.ResourceConfigMaps:             "50",
	corev1.ResourceSecrets:                "50",
}

// Contract: "A NetworkPolicy named default-deny that selects every pod in the
// namespace, lists both policy types, Ingress and Egress, and has no rules."
func TestContractNewNamespaceGetsDefaultDenyPolicy(t *testing.T) {
	ns := newTestNamespace(t)

	waitForDefaultDenyPolicy(t, ns)
}

// Contract: "A ResourceQuota named default-quota whose spec.hard is exactly ..."
func TestContractNewNamespaceGetsDefaultQuota(t *testing.T) {
	ns := newTestNamespace(t)

	waitForDefaultQuota(t, ns)
}

// Contract: "Every namespace it does not skip, including the ones that existed before
// the controller started."
func TestContractNamespaceFromBeforeStartupGetsGuardrails(t *testing.T) {
	waitForDefaultDenyPolicy(t, preexistingNamespace)
	waitForDefaultQuota(t, preexistingNamespace)
}

// Contract: "When a guardrail is deleted by hand, it comes back: a new object with the
// same name and spec."
func TestContractDeletedPolicyComesBack(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	original := waitForDefaultDenyPolicy(t, ns)

	g.Expect(k8sClient.Delete(context.Background(), original)).To(gomega.Succeed())

	waitForReplacement(t, &networkingv1.NetworkPolicy{}, client.ObjectKeyFromObject(original), original.UID)
	waitForDefaultDenyPolicy(t, ns)
}

// Contract: "When a guardrail is deleted by hand, it comes back: a new object with the
// same name and spec."
func TestContractDeletedQuotaComesBack(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	original := waitForDefaultQuota(t, ns)

	g.Expect(k8sClient.Delete(context.Background(), original)).To(gomega.Succeed())

	waitForReplacement(t, &corev1.ResourceQuota{}, client.ObjectKeyFromObject(original), original.UID)
	waitForDefaultQuota(t, ns)
}

// Contract: "Running Reconcile again on a namespace that is already correct changes
// nothing: no new objects, no updates (resourceVersion stays the same)."
func TestContractReconcileIsIdempotent(t *testing.T) {
	g := gomega.NewWithT(t)
	ctx := context.Background()
	ns := newTestNamespace(t)
	waitForDefaultDenyPolicy(t, ns)
	waitForDefaultQuota(t, ns)

	// Give any follow-up reconcile of the creation time to finish before the state is
	// recorded.
	time.Sleep(time.Second)
	policyKey := client.ObjectKey{Namespace: ns, Name: guardrailPolicyName}
	policy := &networkingv1.NetworkPolicy{}
	g.Expect(k8sClient.Get(ctx, policyKey, policy)).To(gomega.Succeed())
	quotaKey := client.ObjectKey{Namespace: ns, Name: guardrailQuotaName}
	quota := &corev1.ResourceQuota{}
	g.Expect(k8sClient.Get(ctx, quotaKey, quota)).To(gomega.Succeed())
	policyCount := countPolicies(g, ns)
	quotaCount := countQuotas(g, ns)

	// Change the namespace in a way the contract does not care about, so that Reconcile
	// runs again on a namespace whose guardrails are already correct.
	namespace := &corev1.Namespace{}
	g.Expect(k8sClient.Get(ctx, client.ObjectKey{Name: ns}, namespace)).To(gomega.Succeed())
	unchanged := namespace.DeepCopy()
	if namespace.Annotations == nil {
		namespace.Annotations = map[string]string{}
	}
	namespace.Annotations["guardrails-test/nudge"] = "1"
	g.Expect(k8sClient.Patch(ctx, namespace, client.MergeFrom(unchanged))).To(gomega.Succeed())

	consistently(t, func(g gomega.Gomega) {
		g.Expect(countPolicies(g, ns)).To(gomega.Equal(policyCount),
			"no NetworkPolicy should be added to or removed from %s", ns)
		g.Expect(countQuotas(g, ns)).To(gomega.Equal(quotaCount),
			"no ResourceQuota should be added to or removed from %s", ns)

		current := &networkingv1.NetworkPolicy{}
		g.Expect(k8sClient.Get(ctx, policyKey, current)).To(gomega.Succeed())
		g.Expect(current.ResourceVersion).To(gomega.Equal(policy.ResourceVersion),
			"the NetworkPolicy should not be updated again once it is correct")
		currentQuota := &corev1.ResourceQuota{}
		g.Expect(k8sClient.Get(ctx, quotaKey, currentQuota)).To(gomega.Succeed())
		g.Expect(currentQuota.ResourceVersion).To(gomega.Equal(quota.ResourceVersion),
			"the ResourceQuota should not be updated again once it is correct")
	}, "the guardrails in %s should stay as they are", ns)
}

// countPolicies returns the number of NetworkPolicies in namespace ns.
func countPolicies(g gomega.Gomega, ns string) int {
	policies := &networkingv1.NetworkPolicyList{}
	g.Expect(k8sClient.List(context.Background(), policies, client.InNamespace(ns))).To(gomega.Succeed())
	return len(policies.Items)
}

// countQuotas returns the number of ResourceQuotas in namespace ns.
func countQuotas(g gomega.Gomega, ns string) int {
	quotas := &corev1.ResourceQuotaList{}
	g.Expect(k8sClient.List(context.Background(), quotas, client.InNamespace(ns))).To(gomega.Succeed())
	return len(quotas.Items)
}

// waitForDefaultDenyPolicy waits until namespace ns holds the contract's NetworkPolicy
// and returns it.
func waitForDefaultDenyPolicy(t *testing.T, ns string) *networkingv1.NetworkPolicy {
	t.Helper()
	key := client.ObjectKey{Namespace: ns, Name: guardrailPolicyName}
	var found *networkingv1.NetworkPolicy
	eventually(t, func(g gomega.Gomega) {
		policy := &networkingv1.NetworkPolicy{}
		g.Expect(k8sClient.Get(context.Background(), key, policy)).To(gomega.Succeed())

		g.Expect(policy.Spec.PodSelector.MatchLabels).To(gomega.BeEmpty(),
			"podSelector should select every pod in the namespace")
		g.Expect(policy.Spec.PodSelector.MatchExpressions).To(gomega.BeEmpty(),
			"podSelector should select every pod in the namespace")
		g.Expect(policy.Spec.PolicyTypes).To(gomega.ConsistOf(
			networkingv1.PolicyTypeIngress, networkingv1.PolicyTypeEgress))
		g.Expect(policy.Spec.Ingress).To(gomega.BeEmpty(), "no ingress rules")
		g.Expect(policy.Spec.Egress).To(gomega.BeEmpty(), "no egress rules")
		found = policy
	}, "the controller should create NetworkPolicy %s as the contract describes", key)
	return found
}

// waitForDefaultQuota waits until namespace ns holds the contract's ResourceQuota and
// returns it.
func waitForDefaultQuota(t *testing.T, ns string) *corev1.ResourceQuota {
	t.Helper()
	key := client.ObjectKey{Namespace: ns, Name: guardrailQuotaName}
	var found *corev1.ResourceQuota
	eventually(t, func(g gomega.Gomega) {
		quota := &corev1.ResourceQuota{}
		g.Expect(k8sClient.Get(context.Background(), key, quota)).To(gomega.Succeed())

		hard := quota.Spec.Hard
		g.Expect(hard).To(gomega.HaveLen(len(expectedQuotaHard)),
			"spec.hard should list exactly %v, got %v", expectedQuotaHard, hard)
		for name, want := range expectedQuotaHard {
			got, ok := hard[name]
			g.Expect(ok).To(gomega.BeTrue(), "spec.hard should include %s", name)
			g.Expect(got.Cmp(resource.MustParse(want))).To(gomega.BeZero(),
				"spec.hard[%s] should be %s, got %s", name, want, got.String())
		}
		found = quota
	}, "the controller should create ResourceQuota %s as the contract describes", key)
	return found
}

// waitForReplacement waits until an object exists at key whose UID differs from
// deletedUID: a new object, not the deleted one.
func waitForReplacement(t *testing.T, obj client.Object, key client.ObjectKey, deletedUID types.UID) {
	t.Helper()
	eventually(t, func(g gomega.Gomega) {
		g.Expect(k8sClient.Get(context.Background(), key, obj)).To(gomega.Succeed())
		g.Expect(obj.GetUID()).NotTo(gomega.Equal(deletedUID))
	}, "a new %s should replace the deleted one (UID %s)", key, deletedUID)
}
