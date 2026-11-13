# Scenario 3 walkthrough: the deployment never becomes ready

Read this only after your attempt and after `make reveal`.

## Trace one deploy end to end

Before the faults, follow a healthy rollout once, so you know what normal looks like:

```bash
kubectl -n lab rollout restart deploy/web
kubectl -n lab get rs -w                      # a new ReplicaSet scales up, the old one down
kubectl -n lab get pods -w                    # Pending -> ContainerCreating -> Running -> Ready
kubectl -n lab rollout status deploy/web
kubectl -n lab rollout history deploy/web
```

The chain: you change the Deployment's pod template → the Deployment controller creates
a new ReplicaSet → the ReplicaSet controller creates Pods (admission checks them here:
ResourceQuota, Pod Security) → the scheduler picks a node → the kubelet pulls the image,
resolves env/config, starts the container → the probes pass → the Pod is Ready → the
Deployment moves on (`maxSurge: 1`, `maxUnavailable: 0`, so the old pods keep serving the
whole time). `progressDeadlineSeconds: 120` turns "stuck" into a condition you can see:
`ProgressDeadlineExceeded`.

Every fault below breaks one link. Find the link:

```bash
kubectl -n lab describe deploy web | sed -n '/Conditions/,$p'
kubectl -n lab get rs                           # did the new ReplicaSet get pods?
kubectl -n lab describe rs <newest>             # FailedCreate events live here
kubectl -n lab get pods -o wide                 # Pending? Waiting? Running but not Ready?
kubectl -n lab describe pod <new-pod>           # events + container state
kubectl -n lab logs <new-pod> --previous        # for crashes
```

## Fault: image pull (`s3-image-pull`)

- **Link.** kubelet → image.
- **Symptom.** New pod `ErrImagePull`, then `ImagePullBackOff`.
- **Trail.** `describe pod` events: `Failed to pull image "...labapp:0.1.1": ... not found`
  (on `kind`, docker.io access denied; on AKS, the ACR manifest is unknown).
  `kubectl -n lab rollout history deploy/web --revision=<n>` shows the new tag.
- **Fix.** Roll back (`kubectl -n lab rollout undo deploy/web`) or build and push the tag.
- **Production habit.** Pin images by tag or digest and push before deploy; check the
  registry (`az acr repository show-tags -n <acr> --repository labapp`).

## Fault: unschedulable (`s3-unschedulable`)

- **Link.** scheduler.
- **Symptom.** New pod `Pending`, no node assigned.
- **Trail.** `describe pod`: `FailedScheduling ... 0/N nodes are available: N node(s)
  didn't match Pod's node affinity/selector`. The pod spec has
  `nodeSelector: {agentpool: gpupool}`; `kubectl get nodes -L agentpool` shows no such pool.
- **Fix.** Remove the nodeSelector (or create the pool if it should exist).
- **Production habit.** Pending is always the scheduler's answer; the reason is in the
  pod's events.

## Fault: failing probe (`s3-failing-probe`)

- **Link.** readiness probe.
- **Symptom.** New pod `Running`, `0/1` Ready, no restarts.
- **Trail.** `describe pod`: `Readiness probe failed: HTTP probe failed with statuscode:
  404`. The probe path is `/ready`; the app serves `/readyz`
  (`kubectl -n lab exec <old-pod> -- python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:8080/readyz').read())"`).
- **Fix.** Probe path `/readyz`.
- **Production habit.** Running-but-not-Ready means readiness; restarts mean liveness or
  a crash. Know which probe you are looking at.

## Fault: missing config (`s3-missing-config`)

- **Link.** kubelet → env/config resolution, before the container starts.
- **Symptom.** New pod `CreateContainerConfigError`.
- **Trail.** `describe pod`: `Error: couldn't find key FEATURE_FLAGS in ConfigMap
  lab/web-config`.
- **Fix.** Add the key to the ConfigMap, or mark the reference `optional: true`, or remove
  it, whichever matches intent.
- **Production habit.** Ship config before the code that reads it.

## Fault: quota rejection (`s3-quota`)

- **Link.** admission, when the ReplicaSet creates pods.
- **Symptom.** No new pod at all. `get pods` shows only the old ones; the new ReplicaSet
  has `DESIRED 1, CURRENT 0`.
- **Trail.** `describe rs <newest>`: `FailedCreate ... exceeded quota: lab-quota,
  requested: requests.memory=900Mi, used: ..., limited: requests.memory=1Gi`.
  `kubectl -n lab describe resourcequota lab-quota`.
- **Fix.** Right-size the request, or raise the quota deliberately.
- **Production habit.** When there is no pod to describe, describe the ReplicaSet.

## Fault: crash loop (`s3-crash-loop`)

- **Link.** the container's own startup.
- **Symptom.** New pod `Error` / `CrashLoopBackOff`, restarts climbing.
- **Trail.** `kubectl -n lab logs <new-pod> --previous`:
  `ConfigError: invalid integer for DB_CONNECT_TIMEOUT='5s'`. The env var is set directly
  on the container (it overrides the ConfigMap value).
- **Fix.** Remove the override or give it an integer.
- **Production habit.** `--previous` shows the crashed container's logs; the current one
  may not have logged anything yet.
