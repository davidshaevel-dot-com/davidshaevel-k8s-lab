# Warm-up walkthrough: a healthy rollout, component by component

Read this after you have done the [exercise](exercise.md) and written your own answers.

A rollout is not one action. It is a chain of independent components. Each one watches
the API server for a change it cares about, does one job, and writes its result back.
The next component reacts to that result. Nothing calls anything else directly.

## The settings that shape this rollout

All of these come from `k8s/base/deployment.yaml` and `k8s/base/pdb.yaml`, unchanged by
the kind and AKS overlays.

| Setting | Value | What it does here |
|---|---|---|
| `replicas` | 2 | Two `web` pods when nothing is changing |
| `strategy` | `RollingUpdate`, `maxSurge: 1`, `maxUnavailable: 0` | At most 3 pods during a rollout, and never fewer than 2 available |
| `minReadySeconds` | not set (0) | A pod counts as available as soon as it is Ready |
| `progressDeadlineSeconds` | 120 | How long the Deployment may go without progress before it reports so in its `Progressing` condition |
| `revisionHistoryLimit` | 0 | Old ReplicaSets are deleted once a rollout completes |
| Readiness probe | `GET /readyz` on port `http` (8080), every 5s, 2 failures to fail | Decides when a pod is Ready |
| Liveness probe | `GET /healthz` on port `http`, every 10s, 3 failures to fail | Decides when the kubelet restarts the container |
| Requests and limits | 50m CPU and 96Mi memory requested; 256Mi memory limit | The scheduler places pods by their requests |
| `imagePullPolicy` | `IfNotPresent` | The kubelet pulls only if the node lacks the image |
| PodDisruptionBudget `web` | `minAvailable: 1` | Guards evictions (node drains, upgrades), not rollouts; see step 7 |

## Step by step

### 1. kubectl and the API server: the change is stored

`kubectl rollout restart deployment/web` sends one PATCH to the Deployment. It sets the
annotation `kubectl.kubernetes.io/restartedAt` in `spec.template.metadata.annotations`
to the current time. That is the whole command. It deletes no pod.

The API server authenticates the request (kind: the client certificate in kind's
kubeconfig; AKS: your Entra ID token, through kubelogin), authorizes it (kind: Kubernetes
RBAC; AKS: Azure RBAC for Kubernetes), runs admission, and stores the new object in
etcd. Because the spec changed, `metadata.generation` goes up by one.

**Where it shows:** the annotation you printed in step 4. There is no event for the
PATCH itself: events are written by the components that react to it, starting with the
next one.

### 2. The Deployment controller: a new ReplicaSet, and the pace of the swap

The Deployment controller runs in kube-controller-manager. It sees the new generation
and hashes the pod template. The annotation changed the template, so the hash no longer
matches the current ReplicaSet's, and the controller creates a new ReplicaSet named
`web-<hash>`. That hash is the `pod-template-hash` label you found in the starting
point; every pod the new ReplicaSet creates carries it too.

The controller then moves replicas from the old ReplicaSet to the new one, within the
strategy's limits: at most 3 pods (2 + `maxSurge: 1`) and at least 2 available
(2 − `maxUnavailable: 0`).

1. New ReplicaSet to 1. There are now 3 pods, and the 2 old ones keep serving.
2. When the new pod is available (Ready, since `minReadySeconds` is 0): old ReplicaSet
   to 1, new ReplicaSet to 2.
3. When the second new pod is available: old ReplicaSet to 0.

At no point are fewer than 2 Ready pods behind the Service. Steps 2 and 3 can land a
moment apart, so their events may interleave slightly.

**Where it shows:** `ScalingReplicaSet` events on `deployment/web`, one per change of
size, with messages like "Scaled up replica set web-… from 0 to 1". The lines that
`rollout status` printed are the same progress, read from the Deployment's status.
`kubectl -n lab describe deployment web` shows the result in `Conditions`: `Available`
is `True` (`MinimumReplicasAvailable`) and `Progressing` is `True`
(`NewReplicaSetAvailable`).

**Clean-up.** With `revisionHistoryLimit: 0`, once the old ReplicaSet is at 0 and its
pods are gone, the controller deletes it. That is why step 4 shows one ReplicaSet. For
the same reason, `kubectl -n lab rollout history deployment/web` lists only the current
revision, even though the revision number (the `deployment.kubernetes.io/revision`
annotation on the Deployment) went up by one.

### 3. The ReplicaSet controller: pods are created and deleted

The ReplicaSet controller, also in kube-controller-manager, keeps each ReplicaSet's
pod count at its `spec.replicas`. When the new ReplicaSet goes to 1, it creates a pod
from the template. When the old one goes down, it deletes one of its pods. Each new pod
gets an `ownerReference` to its ReplicaSet. The API server runs admission on every pod
the controller creates, as it did for your PATCH.

**Where it shows:** `SuccessfulCreate` ("Created pod: web-…") and `SuccessfulDelete`
("Deleted pod: web-…") events on the ReplicaSets, and `Controlled By: ReplicaSet/web-…`
in `describe pod`. The ReplicaSet created the pod, not the Deployment and not you.

### 4. The scheduler: a node for each new pod

A new pod starts with an empty `spec.nodeName`. The scheduler, kube-scheduler, picks a
node in two passes. First it filters out nodes that cannot take the pod: not enough
allocatable CPU or memory for the requests (50m and 96Mi), or a taint the pod does not
tolerate. Then it scores the rest; the default scoring spreads a Deployment's pods across
nodes when it can. Finally it binds the pod by setting `spec.nodeName`.

- **kind:** the control-plane node is tainted `NoSchedule`, so the only candidate is the
  worker, `k8s-lab-worker`. Every `web` pod lands there.
- **AKS:** the `system` pool is tainted `CriticalAddonsOnly=true:NoSchedule` (it runs
  critical add-ons only), so `web` pods go to the `user` pool. With one user node, both
  pods land on it. If the autoscaler has added a second or third node, the scheduler
  tends to put the two pods on different nodes.

**Where it shows:** a `Scheduled` event from `default-scheduler`, "Successfully assigned
lab/web-… to <node>", and the `NODE` column of `get pods -o wide`.

### 5. The kubelet and the container runtime: the container starts

The kubelet on the chosen node watches for pods bound to it. For the new pod it asks the
container runtime (containerd, on both kind and AKS) to create a pod sandbox. The
network plugin gives the pod its IP (kind: kindnet; AKS: Azure CNI Overlay with Cilium,
from the pod range 10.120.0.0/16). The kubelet mounts the `emptyDir` volume at `/tmp`,
gets the image, and starts the container `web` with its security context: user 10001,
a read-only root filesystem and no Linux capabilities. Inside, gunicorn starts its
master process and 2 worker processes on port 8080.

**The image is already on the node.** With `imagePullPolicy: IfNotPresent`, the kubelet
pulls only when the node lacks the image.

- **kind:** `make deploy` loaded `labapp:0.1.0` onto the node with `kind load`, so there
  is nothing to pull.
- **AKS:** the node pulled the image from the lab's container registry the first time it
  ran the app. A new pod on the same node finds it there. A pod placed on a node that
  has never run the app, for example one the autoscaler just added, shows `Pulling` and
  then `Pulled` with a download time instead.

**Where it shows:** `Pulled` (with a message that the image is already present on the
machine), `Created` and `Started` events from `kubelet`, and the pod's `IP` in
`get pods -o wide`.

### 6. The probes: the pod becomes Ready

The kubelet runs both probes. The readiness probe has no initial delay, so its first
`GET /readyz` goes out right after the container starts, then every 5 seconds. One
success makes the container ready, and with it the pod. `/readyz` answers as soon as a
gunicorn worker serves HTTP; it does not check the database (see
[app/README.md](../../app/README.md)). The liveness probe, `GET /healthz` every 10
seconds, keeps passing in the background.

**Where it shows:** a passing probe writes no event. The evidence is in the pod's status:
`Ready` and `ContainersReady` are `True` in the `Conditions` table of `describe pod`,
and `READY` reads `1/1` in `get pods`. The `Readiness` line in `describe pod` shows the
probe as configured, ending `period=5s #success=1 #failure=2`.

The first probe can arrive before gunicorn has opened its port, because gunicorn loads
the app before it listens (`--preload`). If it does, you see one `Unhealthy` warning on
the new pod, and the next probe 5 seconds later passes. A pod that has never been Ready
is simply not Ready yet; `failureThreshold: 2` matters only for a pod that was Ready.

### 7. Back to the Deployment controller: the old pods go

The kubelet reports the pod as Ready to the API server. The Deployment controller sees
one more available pod and takes the next step from section 2: it scales the old
ReplicaSet down, and the ReplicaSet controller deletes an old pod.

Deleting a pod starts a graceful shutdown. The pod is marked as terminating, and its
kubelet sends the container SIGTERM. gunicorn finishes its open requests and exits,
well within the default 30-second grace period, and the pod is removed. While an old pod
shuts down, its readiness probe can fail once the server has stopped; a warning about
that on an old, terminating pod is normal.

**The PodDisruptionBudget plays no part here.** A PDB is checked only for evictions,
such as a node drain or a node-pool upgrade. A rollout deletes pods directly through the
ReplicaSet, so what protects capacity during a rollout is `maxUnavailable: 0`, not
`minAvailable: 1`.

**Where it shows:** a `Killing` event ("Stopping container web") on each old pod, and
`Terminating` in `get pods` for a few seconds.

### 8. The EndpointSlice controller: the Service follows the pods

The EndpointSlice controller, in kube-controller-manager, watches the Service `web` and
every pod that matches its selector, `app.kubernetes.io/name: web`. For each matching pod
that has an IP, it writes an endpoint into the slice for `web`. The endpoint holds the
pod's IP, the port the Service's `targetPort: http` names in that pod (8080), and
`conditions`:

- `ready: false` while the pod is not yet Ready, then `ready: true`;
- for a terminating pod, `ready: false` and `terminating: true`, until the pod is gone
  and the endpoint is removed.

Each endpoint has a `targetRef` naming its pod, and a `nodeName`. The slice carries the
label `kubernetes.io/service-name: web`, which is how the command in step 6 found it.
The controller writes no events for this.

**Where it shows:** after the rollout, the `web` slice lists exactly the two new pods'
IPs, all `ready: true`, on port 8080.

### 9. The Service data path: how traffic reaches a Ready pod

The Service `web` has a ClusterIP and listens on port 80. Nothing listens on that IP.
Instead, every node runs an agent that reads the EndpointSlices and programs the node so
that a connection to the ClusterIP on port 80 goes to one of the ready endpoints on 8080.
New connections go only to endpoints with `ready: true`, which is why a new pod gets no
traffic until its readiness probe passes.

- **kind:** kube-proxy does this, with packet-filter rules on each node.
- **AKS:** with Cilium as the network data plane, the Cilium agent does it with eBPF,
  and the cluster runs no kube-proxy.

`kubectl -n kube-system get daemonsets` shows which agent your cluster runs.

Two things in this lab do not use this path. `kubectl port-forward svc/web` picks one
pod when it starts and tunnels to that pod through the API server and the kubelet. And
`make status` runs its checks with `kubectl exec` inside a Ready pod. The Service data
path is the one that other pods use.

## The whole trace in one table

In the order you saw it. The scale-down of the old ReplicaSet and the scale-up of the
new one can trade places by a moment.

| Event (`REASON`) | On | Reported by | Meaning |
|---|---|---|---|
| none | Deployment `web` | API server | Your PATCH changed the pod template |
| `ScalingReplicaSet` | Deployment `web` | deployment-controller | New ReplicaSet scaled to 1 |
| `SuccessfulCreate` | new ReplicaSet | replicaset-controller | First new pod created |
| `Scheduled` | new pod | default-scheduler | The pod is bound to a node |
| `Pulled` | new pod | kubelet | The image is already present on the node |
| `Created`, `Started` | new pod | kubelet | Container `web` is running |
| none | new pod | kubelet | The readiness probe passed; the pod is Ready |
| `ScalingReplicaSet` | Deployment `web` | deployment-controller | Old ReplicaSet scaled to 1 |
| `SuccessfulDelete` | old ReplicaSet | replicaset-controller | One old pod deleted |
| `Killing` | old pod | kubelet | The old container stops |
| `ScalingReplicaSet` | Deployment `web` | deployment-controller | New ReplicaSet scaled to 2 |
| … | | | The second new pod repeats `SuccessfulCreate` through `Started` |
| `ScalingReplicaSet` | Deployment `web` | deployment-controller | Old ReplicaSet scaled to 0 |
| `SuccessfulDelete`, `Killing` | old ReplicaSet, old pod | replicaset-controller, kubelet | The last old pod goes |
| none | ReplicaSet | deployment-controller | The old ReplicaSet is deleted (`revisionHistoryLimit: 0`) |
| none | EndpointSlice for `web` | endpointslice-controller | It now lists only the two new pods |
