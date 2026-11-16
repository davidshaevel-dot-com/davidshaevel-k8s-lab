//go:build contract && contract_optional

package controller

// Optional contract tests: the extension marked OPTIONAL in the contract above
// Reconcile, restoring a guardrail that someone edited by hand. They are not part of
// "done" for the scenario: make the core contract tests (contract_test.go) pass
// first, then take these on if you have time. Run them with
// `make test-contract-optional`.
//
// They reuse the core group's helpers and fixtures, so they build only with both
// tags: contract and contract_optional.

import (
	"context"
	"testing"

	"github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// Optional contract: "When a guardrail is edited by hand, it goes back to the
// contract's spec."
func TestOptionalEditedPolicyIsRestored(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	policy := waitForDefaultDenyPolicy(t, ns)

	// Someone narrows the policy to Ingress only, which lets all egress out again. A
	// merge patch carries no resourceVersion, so it cannot conflict with the
	// controller's own writes.
	edited := policy.DeepCopy()
	edited.Spec.PolicyTypes = []networkingv1.PolicyType{networkingv1.PolicyTypeIngress}
	g.Expect(k8sClient.Patch(context.Background(), edited, client.MergeFrom(policy))).To(gomega.Succeed())

	waitForDefaultDenyPolicy(t, ns)
}

// Optional contract: "When a guardrail is edited by hand, it goes back to the
// contract's spec."
func TestOptionalEditedQuotaIsRestored(t *testing.T) {
	g := gomega.NewWithT(t)
	ns := newTestNamespace(t)
	quota := waitForDefaultQuota(t, ns)

	// Someone raises the pod limit tenfold.
	edited := quota.DeepCopy()
	edited.Spec.Hard[corev1.ResourcePods] = resource.MustParse("500")
	g.Expect(k8sClient.Patch(context.Background(), edited, client.MergeFrom(quota))).To(gomega.Succeed())

	waitForDefaultQuota(t, ns)
}
