# Scenario 4 walkthrough: the ideas behind a controller

This walkthrough explains the concepts the [exercise](exercise.md) needs. It contains
no solution: no reconcile logic and no code for the contract. Read it before you
start, while you work, or after.

## The reconcile loop

A controller compares the state you want with the state the cluster holds and acts to
close the gap. In controller-runtime that comparison is one function, `Reconcile`,
called with the name of one object, here a namespace. Each call answers one question
for that namespace: "Given what I see now, what must change?" Then it makes those
changes and returns.

`Reconcile` is not told what happened. It gets a name, not an event: not "the
NetworkPolicy was deleted", not "a namespace was created". It looks at the cluster as
it is and works out what to do from that alone. This makes it robust: the same call
handles a new namespace, a deleted guardrail, a missed event and a restart of the
controller.

## Level-triggered, not edge-triggered

An edge-triggered system acts on changes ("X was deleted, so recreate X"). A
level-triggered system acts on state ("X should exist and does not, so create it").
Kubernetes controllers are level-triggered. The difference shows when things go
wrong:

- **Missed events.** If the controller is down when a guardrail is deleted, there is
  no event for it to replay. A level-triggered controller still finds the gap the next
  time it looks: on startup, controller-runtime lists every namespace and reconciles
  each one. That is what `TestContractNamespaceFromBeforeStartupGetsGuardrails` checks.
- **Bursts.** Ten changes to one namespace in quick succession can collapse into one
  call. The work queue holds names, and a name already waiting is not queued again.
- **Ordering.** Calls for different namespaces can run in any order, and a call can
  see a cluster that has moved on since the event that triggered it. Decisions based
  on "what I see now" stay correct; decisions based on "what just happened" do not.

## Desired state, idempotency and churn

Because `Reconcile` can run any number of times, running it on a namespace that is
already right must change nothing. That is idempotency, and
`TestContractReconcileIsIdempotent` checks it by watching each guardrail's
`resourceVersion`: every write the API server accepts bumps it, so a value that stays
the same means nothing was written.

Two broad ways to write desired state:

- **Read, compare, write.** Read the current object, create it if missing, update it
  if it differs, do nothing if it matches. The API server skips an update that changes
  nothing, so the `resourceVersion` stays put, but only if your comparison and your
  desired object agree with what the server stores. Fields the server fills in with
  defaults are the usual trap: a desired object that leaves them out can look
  "different" on every pass.
- **Server-side apply.** Send the fields you own and let the API server merge them,
  tracking which manager owns which field. The server works out whether anything
  changed.

Either can meet the contract. Each has its own failure mode to watch for: an update
loop with the first, and field ownership conflicts with the second.

## Watches and ownership

`Reconcile` runs only when something the controller watches changes. The scaffold's
`SetupWithManager` watches namespaces. That covers a new namespace, and the
reconciles at startup. It does not cover a guardrail deleted by hand: the namespace
did not change, so nothing calls `Reconcile` for it.

To bring a deleted guardrail back, a change to a NetworkPolicy or ResourceQuota must
lead to a `Reconcile` of its namespace. controller-runtime offers two ways to watch
other kinds of object:

- **Owned objects.** When an object carries an owner reference to the object being
  reconciled, the builder's `Owns` watch maps each change to the owner. A
  namespace-scoped object can name a cluster-scoped owner such as a Namespace. Owner
  references also feed garbage collection: when the owner is deleted, what it owns
  goes too.
- **Mapped watches.** The builder's `Watches` takes any kind of object and a function
  that turns each change into the names to reconcile. It needs no owner reference.

The choice changes what the cluster holds (an owner reference or not) and how the
controller recognises "its" objects. Which you pick also bears on the decision about
objects with a guardrail's name that your controller did not create.

Every watch of a kind adds an informer, which lists that kind across the whole cluster
and keeps it in memory. Watching NetworkPolicies cluster-wide is cheap in a lab and a
real cost in a large cluster. Informers can be filtered (by label, for example).

## The cache and the client

The manager's client reads from its cache, which its informers fill, and writes to
the API server. Two consequences:

- **Reads can be stale.** Right after a create, the cache may not have the new object
  yet. A `Reconcile` that runs in that window can decide the object is missing. An
  attempt to create it again fails with "already exists", which is safe to treat as
  "someone already did it": the next reconcile sees the object.
- **Writes can conflict.** An update carries the `resourceVersion` it read. If the
  object changed in between, the API server refuses it with a conflict. Returning the
  error retries the whole `Reconcile`, which reads again: level-triggered behaviour
  handles it.

The tests read through their own client, with no cache, so they always see the API
server's current state.

## Results, errors and requeues

What `Reconcile` returns decides what happens next:

- **No error, empty Result.** Done until a watched object changes again.
- **An error.** The name goes back on the queue with exponential backoff (a few
  milliseconds at first, growing up to minutes). Use it for failures that may succeed
  later. If you return an error, any Result alongside it is ignored.
- **`RequeueAfter`.** Come back after this long, without an error. Useful when the
  controller waits on something it cannot watch. Nothing in this contract needs it:
  the watches cover every change.
- **Terminal errors.** controller-runtime can mark an error as not worth retrying
  (`reconcile.TerminalError`). A namespace being deleted is a case of "nothing to do",
  not an error at all.

Also, every controller-runtime manager re-lists everything it watches periodically
(the sync period, hours by default), so even a controller with a missing watch
eventually corrects drift. "Eventually" is far too slow for the tests, which wait 10
seconds, and for anyone deleting guardrails by hand.

## RBAC

A controller acts with an identity, and that identity needs permission for every verb
it uses on every kind:

- **Running locally** (`make run`), the controller uses your kube context's identity.
  On a kind cluster that is cluster-admin, so a missing permission never shows.
- **Running in a cluster,** it uses its pod's ServiceAccount, bound to a ClusterRole
  (namespaces and guardrails are cluster-wide concerns). A missing verb shows up as a
  `forbidden` error at the first call that needs it, which is often long after
  startup.

Watching a kind needs `list` and `watch`, not only `get`: the informer lists and then
watches. The contract lists the RBAC the logic will need. Kubebuilder projects
generate the ClusterRole from `+kubebuilder:rbac` comments; this scaffold uses no
generator, so the list is written out by hand.

## The ResourceQuota: why it counts objects

The contract's quota limits object counts only: pods, services, persistent volume
claims, config maps and secrets. It sets no `requests.cpu` or `requests.memory`.

That is deliberate. Once a namespace has a quota on a compute resource, the API server
rejects every new pod that does not declare that resource, unless a LimitRange in the
namespace fills in a default. A controller that put a compute quota into every
namespace would make every pod without requests fail to start, in every namespace it
touches, the moment it ran. Counting objects guards against runaway creation without
that side effect. A real platform would pair compute quotas with LimitRanges, or set
quotas per team.

## Testing with envtest

envtest starts a real `kube-apiserver` and `etcd` on your machine, from binaries that
`setup-envtest` downloads. The API, validation, defaulting and admission are real.
Nothing else of Kubernetes runs:

- **No controllers.** No kube-controller-manager. A deleted namespace stays in
  `Terminating` forever, because the namespace controller that would empty and remove
  it is not there. Garbage collection does not run either, so deleting an owner
  deletes nothing it owns. The tests use a fresh namespace each and never depend on
  namespace deletion finishing.
- **No nodes.** No scheduler, no kubelet: pods are never scheduled or started. These
  tests need none.
- **No quota accounting.** The ResourceQuota controller is absent, so a quota's
  `status` stays empty. The tests check `spec` only.

The tests poll: "eventually this holds" for things the controller must do, and
"consistently this holds" for things it must not do. Polling with a timeout fits a
level-triggered controller, which reaches the right state soon, without promising
when.

The two groups of tests are separate. The smoke tests prove the harness works. The
contract tests sit behind a build tag (`//go:build contract`) so that plain
`go test ./...` stays green on the scaffold, and `make test-contract` turns them on.

## The decisions the contract leaves open

The contract states these as questions. Questions to think through for each:

- **Skipped namespaces.** What breaks if a default-deny policy lands in `kube-system`?
  Should the rule be a fixed list, a label on the namespace, or both? Which way does
  it fail when someone adds a new system namespace later?
- **Objects you did not create.** If `default-deny` already exists and someone else
  made it, is overwriting it right, or is it someone's deliberate choice? How would
  your controller tell the difference, and what should a person see when it declines
  to act?
