# Scenario 4: namespace guardrails controller

The ticket ([scenario.txt](scenario.txt)): every namespace should carry a default-deny
NetworkPolicy and a ResourceQuota, and both keep disappearing. You write a small
controller in Go that creates them in every namespace and puts them back when someone
removes them, with tests that run against envtest.

This scenario is a build, not a diagnosis.

- **Nothing is planted.** Do not run `make plant` for it. There is no timer and no
  `make reveal`.
- **The scaffold is ready.** A Go project with controller-runtime, an envtest harness,
  tests and a Makefile are in [controller/](controller/). `Reconcile` is empty apart
  from its contract, written as comments. You write the logic.
- **The tests are your target.** The smoke tests pass on the scaffold. The core
  contract tests fail until your logic does what the contract says, and go green as
  you write it. When they all pass, the scenario is done. A separate group of
  optional tests covers an extension (restoring a guardrail someone edited by hand)
  for when you have time.
- **No cluster needed until the last step.** The tests run against envtest: a real
  API server and etcd on your machine, with nothing else of Kubernetes.
- **[walkthrough.md](walkthrough.md) explains the ideas, not the code.** It holds no
  solution. Read it before you start, or when you are stuck.

## Who wrote what

The scaffold (the Go project, `main.go`, the empty `Reconcile` and its contract, the
`SetupWithManager` stub), the envtest harness, the smoke tests, both groups of
contract tests (core and optional), the Makefile, this text,
[walkthrough.md](walkthrough.md) and [scenario.txt](scenario.txt) were built with AI
coding agents under David Shaevel's direction. The reconcile logic, the watches it
needs, the optional extension if he takes it on, the decisions the contract leaves
open and the tests for those decisions are his.

## Prerequisites

Install these first.

| Tool | Version | Tested with | Needed for |
|---|---|---|---|
| Go | 1.26 or newer (the repo pins 1.26.11 in `.tool-versions`) | 1.26.11 (darwin/arm64) | everything |
| GNU make | 3.81 or newer | 3.81 | everything |
| Internet access | | | the first build (Go modules) and the first test run (envtest binaries) |
| kubectl | 1.36 or newer | 1.37.0, for the `make run` context check only | step 11 only |
| Docker Desktop (running) and kind | as in the repo's [README](../../README.md#prerequisites) | not run with this scenario | step 11 only |

Go: use any installer. One way is [asdf](https://asdf-vm.com/) with its `golang`
plugin, which reads the version from `.tool-versions` at the repo root. Another is the
installer from [go.dev/dl](https://go.dev/dl/). Nothing in the lab requires asdf.

The Makefile fetches everything else itself, at pinned versions:

| What | Pinned version | Where it goes |
|---|---|---|
| `sigs.k8s.io/controller-runtime` | v0.24.1 (the release for Kubernetes 1.36) | Go module cache |
| `k8s.io/api`, `k8s.io/apimachinery`, `k8s.io/client-go` | v0.36.5 (the lab cluster's version) | Go module cache |
| `github.com/onsi/gomega` | v1.39.0 | Go module cache |
| `setup-envtest` | v0.24.1, run with `go run`, never installed | Go module cache |
| envtest binaries (kube-apiserver, etcd, kubectl) | Kubernetes 1.36.2 | `controller/bin/k8s/k8s/1.36.2-<os>-<arch>/` (gitignored) |

These are the versions the scaffold's tests were run with.

The envtest binaries are 1.36.2, not 1.36.5 like the lab cluster: no 1.36.5 build of
them is published, and 1.36.2 is the newest 1.36 build. Patch releases do not change
the API, so the tests are not affected.

## The steps

Run them in order, from the repo root unless a step says otherwise.

### 1. Go to the controller's directory

```bash
cd scenarios/4-namespace-guardrails-controller/controller
```

Every `make` target in this exercise up to step 10 runs from here. Run `make help` to
list them.

### 2. Check Go

```bash
go version
```

It must print `go1.26` or newer. If it prints `command not found`, install Go first
(see Prerequisites).

### 3. Build and vet the scaffold

```bash
make build
make vet
```

The first run downloads the Go modules, which takes a minute. Both end without an
error. `make vet` also checks both groups of contract tests, which plain
`go vet ./...` would skip (they sit behind build tags; see step 5).

### 4. Run the smoke tests (they pass)

```bash
make test-smoke
```

The first run downloads the envtest binaries to a folder under `bin/k8s/`. The tests
start a local
API server and etcd, start the controller's manager against them, and check three
things: the API server answers with version 1.36, the manager is running, and a
namespace can be created. Expect three `--- PASS` lines and `ok` at the end.

### 5. Run the core contract tests (they fail, and that is expected)

```bash
make test-contract
```

This is your target. Each contract test creates a namespace, waits up to 10 seconds
for the cluster to reach the state the contract describes, and fails if it does not.
With an empty `Reconcile`, nothing ever appears, so all six fail, after about a
minute in total. Between the controller's log lines, each failure looks like this
(the namespace name is random, and the path is shortened here):

```text
=== RUN   TestContractDeletedPolicyComesBack
    contract_test.go:76:
        Timed out after 10.001s.
        the controller should create NetworkPolicy guardrails-test-lpchx/default-deny as the contract describes
        The function passed to Eventually failed at .../internal/controller/contract_test.go:168 with:
        Expected success, but got an error:
            <*errors.StatusError | 0x53556b49c960>:
            networkpolicies.networking.k8s.io "default-deny" not found

--- FAIL: TestContractDeletedPolicyComesBack (10.02s)
```

and the run ends with:

```text
FAIL	github.com/davidshaevel-dot-com/davidshaevel-k8s-lab/scenarios/4-namespace-guardrails-controller/controller/internal/controller	63.894s
FAIL
make: *** [test-contract] Error 1
```

Read the failures as statements about the cluster: "the controller should create
NetworkPolicy ... as the contract describes", then the reason, here `not found`. The
first line of each (`contract_test.go:76`) is the line in the test that was waiting.
A failure that mentions compiling, `KUBEBUILDER_ASSETS` or starting envtest is not one
of these: it means the setup is broken, so fix that before you go on.

Stopping a run with Ctrl-C is fine: the harness stops the local API server and etcd
before it exits. If a run ends any other way (a `go test` timeout, a killed terminal),
they can keep running in the background; `make stop-envtest` stops them.

The six core tests, and the line of the contract each one encodes. When all six
pass, the scenario is done.

| Test | Contract line |
|---|---|
| `TestContractNewNamespaceGetsDefaultDenyPolicy` | A NetworkPolicy named `default-deny` that selects every pod, lists Ingress and Egress, and has no rules |
| `TestContractNewNamespaceGetsDefaultQuota` | A ResourceQuota named `default-quota` with exactly the listed `spec.hard` |
| `TestContractNamespaceFromBeforeStartupGetsGuardrails` | Every namespace it does not skip, including the ones that existed before the controller started |
| `TestContractDeletedPolicyComesBack` | A guardrail deleted by hand comes back |
| `TestContractDeletedQuotaComesBack` | A guardrail deleted by hand comes back |
| `TestContractReconcileIsIdempotent` | Running again on a correct namespace changes nothing |

The optional group, `make test-contract-optional`, fails the same way for now. It is
not part of "done"; step 10 comes back to it.

| Optional test | Contract line (marked OPTIONAL) |
|---|---|
| `TestOptionalEditedPolicyIsRestored` | A guardrail edited by hand goes back to the contract's spec |
| `TestOptionalEditedQuotaIsRestored` | A guardrail edited by hand goes back to the contract's spec |

### 6. Read the contract

Open [controller/internal/controller/guardrails.go](controller/internal/controller/guardrails.go).
The comment above `Reconcile` is the contract: what the controller watches, what it
ensures, what happens when a guardrail is deleted by hand, the optional extension for
hand edits, idempotency, what to return and when to requeue, and the RBAC the logic
will need. The test files are `suite_test.go` (the harness), `smoke_test.go`,
`contract_test.go` (core) and `contract_optional_test.go` (optional) in the same
directory.

### 7. Make the decisions the contract leaves to you

Write each one down, with your reason, before you write the code:

- **Which namespaces to skip.** A default-deny policy in a namespace that belongs to
  the cluster itself can cut its pods off from DNS and the API server. Your rule must
  not skip namespaces named `guardrails-test-*`, which the tests use.
- **What to do when an object with a guardrail's name already exists and your
  controller did not create it.** The lab's own namespace `lab` is such a case: it
  already carries a NetworkPolicy named `default-deny`. (Its ResourceQuota is named
  `lab-quota`, so only the policy's name collides.)

### 8. Write the logic until the core contract tests pass

Two places in `guardrails.go`:

- `Reconcile`, which brings one namespace to the contract's state.
- `SetupWithManager`, which so far watches only namespaces. A guardrail deleted by
  hand comes back only if a change to a guardrail leads back to its namespace.

Run `make test-contract` as you go. Each test that turns green is one more line of the
contract your code meets. `make test-smoke` and `make vet` must stay green too.

### 9. Add tests for your decisions

Add contract tests to `contract_test.go` for the decisions from step 7: a namespace
your rule skips gets no guardrails, and the case of an existing object with a
guardrail's name behaves as you decided. Follow the existing tests: assert on what the
cluster holds, not on how your code got there.

- **Where and how to name them.** Put them in `contract_test.go` and start each name
  with `TestContract`: `make test-contract` runs only tests with that prefix, and the
  shared helpers exist only under the `contract` build tag. A test named otherwise, or
  in an untagged file, never runs (or breaks `make test-smoke`).
- **Objects that must exist before the controller sees the namespace.** Inside a test
  function, the controller starts on a namespace the moment the test creates it, so
  the test races it. The race-free place is the setup in `suite_test.go` that creates
  `guardrails-test-preexisting` before the manager starts: add what such a test needs
  there.
- **Contract lines no test covers.** A namespace that is being deleted, the return
  values, and the RBAC list have no test, and nothing in this exercise runs the
  controller with less than admin rights. A test for the namespace being deleted is
  possible on envtest (a deleted namespace stays in `Terminating` there); the others
  are for reading, not testing.

### 10. Optional: restore hand-edited guardrails

Only once `make test-contract` is fully green. The contract's OPTIONAL section asks
the controller to put a hand-edited guardrail's spec back, and poses the question to
think about first. Work against:

```bash
make test-contract-optional
```

`make test-contract` must stay green while you do. Skipping this step leaves the
scenario done.

### 11. See it work on a cluster

Use a local kind cluster. Do not point the controller at a shared or production
cluster: it changes every namespace it does not skip, and your skip rule decides
whether that includes the cluster's own.

> **Not on the AKS lab cluster.** It is billable and shared with the other
> scenarios, and a guardrail in the wrong namespace there breaks scenarios 2 and 3.

Go back to the repo root (you are still in the controller's directory from step 1).
`make kind-up` creates the kind cluster `k8s-lab`, or reuses it if it already exists.
A cluster left over from scenarios 2 or 3 still holds the lab app in namespace `lab`,
and the cleanup at the end of this step deletes the whole cluster. If you want a fresh
one, run `make kind-down` first.

```bash
cd ../../..
make kind-up
kubectl get namespaces
```

`make kind-up` switches your kube context to `kind-k8s-lab`. The namespace list is
what your skip rule will meet: the cluster's own namespaces (kind adds one of its own
to the usual `kube-*` ones), plus `default`, plus `lab` if the app is deployed.

Terminal one, from the controller's directory:

```bash
cd scenarios/4-namespace-guardrails-controller/controller
make run KUBE_CONTEXT=kind-k8s-lab
```

`make run` refuses to start unless `KUBE_CONTEXT` names your current context, so you
always say which cluster it is about to change. That check lives in the `make run`
recipe only: `go run .` and the built binary use your current context without asking,
and a `KUBE_CONTEXT` exported in your shell satisfies a bare `make run`. Leave it
running and watch its log.

Terminal two:

```bash
kubectl get networkpolicy,resourcequota -A
kubectl create namespace guardrails-demo
kubectl -n guardrails-demo get networkpolicy,resourcequota
kubectl -n guardrails-demo get networkpolicy --watch --output-watch-events
```

`--output-watch-events` adds an `EVENT` column (`ADDED`, `MODIFIED`, `DELETED`);
without it, a watch does not show deletions. Leave it running and open a third
terminal:

```bash
kubectl -n guardrails-demo delete networkpolicy default-deny
```

In terminal two, a `DELETED` line is followed within a second or two by an `ADDED`
line for a new `default-deny`. Then do the same for the quota: in terminal two, stop
the watch with Ctrl-C and start it again for `resourcequota`
(`kubectl -n guardrails-demo get resourcequota --watch --output-watch-events`), and in
terminal three run `kubectl -n guardrails-demo delete resourcequota default-quota`. If
your logic logs, find in terminal one the lines of the reconciles your deletes caused;
the scaffold itself logs nothing per reconcile.

Then check your skip rule:

```bash
kubectl get networkpolicy -A
```

Every namespace your rule does not skip should have a `default-deny`, and none of the
namespaces it skips should.

When you are done: Ctrl-C in terminals one and two, then, from the repo root:

```bash
kubectl delete namespace guardrails-demo
make kind-down
```

## Afterwards

1. Write down, in your own words, what you built: the decisions from step 7 and why,
   how a deleted guardrail finds its way back to `Reconcile`, and what surprised you.
2. Read [walkthrough.md](walkthrough.md) again and compare.
