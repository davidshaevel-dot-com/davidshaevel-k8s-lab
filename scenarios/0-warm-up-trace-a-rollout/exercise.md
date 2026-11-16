# Warm-up: trace a healthy rollout

Do this once, before the numbered scenarios. You trigger a rollout of the `web`
Deployment yourself and follow it from the change you submit to new pods that are
running, Ready and listed behind the Service. Nothing is broken. The goal is to know what
a normal rollout looks like, and which part of Kubernetes does each step, before you
meet one that goes wrong.

- **Nothing is planted.** Do not run `make plant` for the warm-up: it is only for the
  numbered scenarios (2 and 3). There is no timer and no `make reveal`.
- **Both paths.** The steps work on the local `kind` cluster and on the AKS lab cluster.
  The few differences are listed at the end.
- **A second look in the Azure portal (optional, AKS only).** Some steps end with a note
  on where the portal shows the same thing; [docs/azure-portal.md](../../docs/azure-portal.md) maps the whole lab.
  `kubectl` stays the primary tool: answer each question from its output first. kind
  has no portal.
- **Answer the questions from what you see,** and write the answers down. Read
  [walkthrough.md](walkthrough.md) only after you have finished, then compare.

You need two terminals, both in the repo directory.

## Before you start

**1. The app is healthy.**

```bash
make status
```

It must end with `HEALTHY`. If a fault from an earlier run is still planted, or you are
not sure, run `make heal` and then `make status` again. `make heal` is safe when nothing
is planted, and you do not need `make reveal` first.

**2. kubectl points at the lab cluster.** The `make` targets always talk to the lab
cluster, but the plain `kubectl` commands below use your current context.

```bash
kubectl config current-context
```

It must print `kind-k8s-lab` (kind) or `k8s-lab-aks` (AKS). If it prints anything else,
switch with `kubectl config use-context kind-k8s-lab` or
`kubectl config use-context k8s-lab-aks`. The current context is saved in your
kubeconfig file, so one switch covers both terminals.

**3. Write down the starting point.**

```bash
kubectl -n lab get deploy,rs,pods -o wide
kubectl -n lab get pods -l app.kubernetes.io/name=web --show-labels
```

Write down the ReplicaSet's name and the names of the two `web` pods.

- The ReplicaSet is named `web-` plus a suffix, and each pod is named after the
  ReplicaSet plus a suffix of its own. Where else does the ReplicaSet's suffix appear?

*Second look in the portal (AKS only, optional):* `k8s-lab-aks` → Kubernetes resources
→ Workloads → Deployments → `web` → Overview. Under Workloads, the Replica sets tab lists
the same ReplicaSet as "Current replica set", and the Pods tab lists the two pods with
their Node and Pod IP. Show labels adds the labels.

## Two things to expect

- `kubectl rollout restart` does not delete or restart any pod itself. It stamps an
  annotation on the Deployment's pod template, and that change alone is enough to roll
  out a fresh pair of pods.
- When the rollout finishes, the old ReplicaSet is gone, not left at zero replicas. This
  Deployment keeps no revision history.

## The steps

Run them in order. Steps 2 and 3 go back to back.

### 1. Watch the events (terminal one, leave it running)

```bash
kubectl -n lab get events --watch-only
```

`--watch-only` prints only events from now on. Plain `--watch` would first list the last
hour's events, including any from earlier runs, and mix them into this trace. Nothing
appears until step 2.

- As lines appear, note two columns for each: `REASON` and `OBJECT`. Which kinds of
  object show up, and in what order?

*Second look in the portal (AKS only, optional):* `web` → Events shows the
Deployment's events, with "Last seen" in UTC rather than as an age. It does not stream;
use Refresh.

### 2. Trigger the rollout (terminal two)

```bash
kubectl -n lab rollout restart deployment/web
```

- This command touched no pod, yet pods are about to be replaced. What did it change,
  and on which object? (Step 4 lets you check.)

### 3. Follow the rollout until it finishes (terminal two, right away)

```bash
kubectl -n lab rollout status deployment/web
```

It returns when the rollout is complete. Copy the lines it printed.

- What do those lines tell you about the order in which new pods come up and old pods
  go away? At any moment, how many `web` pods were serving?
- In terminal one, find the events that line up with each of those lines. Which object
  is each event about?

### 4. Look at the result (terminal two)

```bash
kubectl -n lab get deploy,rs,pods -o wide
kubectl -n lab get deployment web -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

- How many ReplicaSets are there now, and is the one from your starting point among
  them? Where did it go?
- Which pods are new? On which node did each one land (the `NODE` column)?
- What did step 2 add to the pod template?

You may still see an old pod in `Terminating` for a few seconds. If so, run the first
command again.

*Second look in the portal (AKS only, optional):* `web` → Overview. Compare Replicas
and Rolling update strategy with what `rollout status` printed, and the Replica sets
tab's "Current replica set" and "Old replica sets" with the first command's output.
The YAML tab shows the pod template's annotations; look, but do not edit there. One
field is known to disagree with the Deployment's spec; see
[docs/azure-portal.md](../../docs/azure-portal.md) and trust `kubectl`.

### 5. Read one new pod's story (terminal two)

The first line picks the newest `web` pod, which is one of the two the rollout created.

```bash
POD=$(kubectl -n lab get pods -l app.kubernetes.io/name=web --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
echo "$POD"
kubectl -n lab describe pod "$POD"
```

Read the `Events` table at the bottom from top to bottom.

- Which component reported each event (the `From` column)?
- What did the scheduler decide, and where does it say so? Where else in the output
  does that decision show up?
- Did the kubelet pull the image from a registry? How can you tell?
- What does `Controlled By` say, and what does it tell you about who created this pod?
- Find the `Liveness` and `Readiness` lines. What does each one check, and how often?
- No event says that a probe passed. How can you tell that the readiness probe passed,
  and roughly when? (Look at `Conditions`.)

*Second look in the portal (AKS only, optional):* Workloads → Pods, filtered to
namespace `lab`, then the pod, shows its details and events; `web` → Live logs →
Select a Pod streams its logs, like `kubectl -n lab logs -f <pod name>`.

### 6. Find the pods behind the Service (terminal two)

```bash
kubectl -n lab get endpointslices
kubectl -n lab get endpointslices -l kubernetes.io/service-name=web -o yaml
```

The first command also lists a slice for the Service `postgres`, the app's database.
This exercise is about the slice for `web`.

- Which addresses does the `web` slice list? Do they match the new pods' IPs from
  step 4? Are any old pod IPs still there?
- The Service `web` listens on port 80. Which port does the slice list, and why?
- In the YAML, what links each endpoint to its pod, and what do its `conditions` say?

*Second look in the portal (AKS only, optional):* the portal has no page for
EndpointSlices. Services, gateways and ingresses shows the Service `web` itself; the
slice is read with `kubectl`.

Stop the watch in terminal one with Ctrl-C.

## Afterwards

1. Run `make status`. It should end with `HEALTHY` again.
2. Write down, in your own words, what each step was and which part of Kubernetes did
   it, from your `rollout restart` to the new pods behind the Service. Copy
   [`runs/TEMPLATE-warm-up.md`](../../runs/TEMPLATE-warm-up.md) to
   `runs/YYYY-MM-DD-s0-warm-up.md` and fill it in.
3. Then read [walkthrough.md](walkthrough.md) and compare.

## kind and AKS: what differs

| | kind | AKS |
|---|---|---|
| Context | `kind-k8s-lab` | `k8s-lab-aks` |
| Where `web` pods run | the one worker node, `k8s-lab-worker` | a node in the `user` pool (it scales from 1 to 3 nodes) |
| Other pods in `lab` | `postgres-0`, the in-cluster database | none: the database is outside the cluster |
| The image | `labapp:0.1.0`, loaded onto the node by `make deploy` | `labapp:0.1.0` from the lab's container registry, pulled by the node the first time it ran the app |
| Azure portal | none | an optional second look; see [docs/azure-portal.md](../../docs/azure-portal.md) |
