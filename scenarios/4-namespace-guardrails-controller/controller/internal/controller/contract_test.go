//go:build contract

package controller

// Contract tests: each one encodes one line of the contract written above Reconcile
// in guardrails.go. They fail until the reconcile logic exists, and they go green as
// you write it. Run them with `make test-contract`; plain `go test ./...` leaves them
// out (build tag "contract").
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
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)

	waitForDefaultDenyPolicy(g, ns)
}

// Contract: "A ResourceQuota named default-quota whose spec.hard is exactly ..."
func TestContractNewNamespaceGetsDefaultQuota(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)

	waitForDefaultQuota(g, ns)
}

// Contract: "Every namespace it does not skip, including the ones that existed before
// the controller started."
func TestContractNamespaceFromBeforeStartupGetsGuardrails(t *testing.T) {
	g := gomega.NewWithT(t)

	waitForDefaultDenyPolicy(g, preexistingNamespace)
	waitForDefaultQuota(g, preexistingNamespace)
}

// Contract: "When a guardrail is deleted by hand, it comes back: a new object with the
// same name and spec."
func TestContractDeletedPolicyComesBack(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	original := waitForDefaultDenyPolicy(g, ns)

	g.Expect(k8sClient.Delete(context.Background(), original)).To(gomega.Succeed())

	waitForReplacement(g, &networkingv1.NetworkPolicy{}, client.ObjectKeyFromObject(original), original.UID)
	waitForDefaultDenyPolicy(g, ns)
}

// Contract: "When a guardrail is deleted by hand, it comes back: a new object with the
// same name and spec."
func TestContractDeletedQuotaComesBack(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	original := waitForDefaultQuota(g, ns)

	g.Expect(k8sClient.Delete(context.Background(), original)).To(gomega.Succeed())

	waitForReplacement(g, &corev1.ResourceQuota{}, client.ObjectKeyFromObject(original), original.UID)
	waitForDefaultQuota(g, ns)
}

// Contract: "Running Reconcile again on a namespace that is already correct changes
// nothing: no new objects, no updates (resourceVersion stays the same)."
func TestContractReconcileIsIdempotent(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	waitForDefaultDenyPolicy(g, ns)
	waitForDefaultQuota(g, ns)

	// Give any follow-up reconcile of the creation time to finish before the
	// resourceVersions are recorded.
	time.Sleep(time.Second)
	ctx := context.Background()
	policy := &networkingv1.NetworkPolicy{}
	g.Expect(k8sClient.Get(ctx, client.ObjectKey{Namespace: ns, Name: guardrailPolicyName}, policy)).To(gomega.Succeed())
	quota := &corev1.ResourceQuota{}
	g.Expect(k8sClient.Get(ctx, client.ObjectKey{Namespace: ns, Name: guardrailQuotaName}, quota)).To(gomega.Succeed())

	consistently(g, func(g gomega.Gomega) {
		policies := &networkingv1.NetworkPolicyList{}
		g.Expect(k8sClient.List(ctx, policies, client.InNamespace(ns))).To(gomega.Succeed())
		g.Expect(policies.Items).To(gomega.HaveLen(1), "exactly one NetworkPolicy in %s", ns)

		quotas := &corev1.ResourceQuotaList{}
		g.Expect(k8sClient.List(ctx, quotas, client.InNamespace(ns))).To(gomega.Succeed())
		g.Expect(quotas.Items).To(gomega.HaveLen(1), "exactly one ResourceQuota in %s", ns)

		g.Expect(policies.Items[0].ResourceVersion).To(gomega.Equal(policy.ResourceVersion),
			"the NetworkPolicy should not be updated again once it is correct")
		g.Expect(quotas.Items[0].ResourceVersion).To(gomega.Equal(quota.ResourceVersion),
			"the ResourceQuota should not be updated again once it is correct")
	}, "the guardrails in %s should stay as they are", ns)
}

// waitForDefaultDenyPolicy waits until namespace ns holds the contract's NetworkPolicy
// and returns it.
func waitForDefaultDenyPolicy(g *gomega.WithT, ns string) *networkingv1.NetworkPolicy {
	key := client.ObjectKey{Namespace: ns, Name: guardrailPolicyName}
	var found *networkingv1.NetworkPolicy
	eventually(g, func(g gomega.Gomega) {
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
func waitForDefaultQuota(g *gomega.WithT, ns string) *corev1.ResourceQuota {
	key := client.ObjectKey{Namespace: ns, Name: guardrailQuotaName}
	var found *corev1.ResourceQuota
	eventually(g, func(g gomega.Gomega) {
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
func waitForReplacement(g *gomega.WithT, obj client.Object, key client.ObjectKey, deletedUID types.UID) {
	eventually(g, func(g gomega.Gomega) {
		g.Expect(k8sClient.Get(context.Background(), key, obj)).To(gomega.Succeed())
		g.Expect(obj.GetUID()).NotTo(gomega.Equal(deletedUID))
	}, "a new %s should replace the deleted one (UID %s)", key, deletedUID)
}
