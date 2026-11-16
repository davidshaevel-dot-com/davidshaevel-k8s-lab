# davidshaevel-k8s-lab

Hands-on Kubernetes practice lab: AKS scenarios with planted faults.

Each scenario is an alert or a ticket on a real cluster. A script plants a fault at random
and does not say which one; you diagnose it with `kubectl` (and the Azure CLI where it
matters), fix it, write down the cause, and only then ask the lab what it planted. Every
run leaves a run log in `runs/`.

> The scenarios and fault scripts were built with AI coding agents under David Shaevel's
> direction; the runs and the run logs are his.

## Prerequisites

Install these first. Versions are the ones the lab was tested with; newer should work.

| Tool | Tested version | Needed for |
|---|---|---|
| GNU make | 3.81 | everything |
| curl, openssl | macOS defaults | finding your IP; generating lab passwords |
| Python | 3.12 | `make test`, and the scripts use `python3` for small JSON chores |
| kubectl | 1.37.0 | everything |
| Docker Desktop (running) | 29.9.2 | the local `kind` path |
| kind | 0.33.0 | the local `kind` path |
| Azure CLI (`az`) | 2.90.0 | the AKS path |
| Terraform | 1.16.2 | the AKS path |
| kubelogin | untested: not installed on the build machine | the AKS path (Entra ID sign-in) |

On macOS: `brew install kubectl kind azure-cli hashicorp/tap/terraform Azure/kubelogin/kubelogin`
(or `az aks install-cli` for kubectl + kubelogin), and Docker Desktop from docker.com.

The AKS path also needs an Azure role that can create role assignments on the
subscription (Owner, or Contributor plus User Access Administrator): Terraform grants
the cluster identities and you their roles.

## Two ways to run the lab: kind and AKS

[kind](https://kind.sigs.k8s.io/) ("Kubernetes in Docker") is a tool from the Kubernetes
project that runs a whole cluster on one machine, with each node as a Docker container.
It was made for testing Kubernetes itself and for local development. It is free and
needs only Docker.

How this lab uses it:

- **The cluster.** `make kind-up` checks that Docker is running, then creates a cluster
  named `k8s-lab` from `kind/cluster.yaml`: one control-plane node and one worker. It
  waits up to two minutes for the nodes, switches `kubectl` to the context
  `kind-k8s-lab`, and lists the nodes. If the cluster already exists, it leaves it as it
  is. kind's default network plugin, kindnet, enforces NetworkPolicy, so the app's
  policies apply here as they do on AKS.
- **The image.** `make deploy` builds `labapp:0.1.0` with your local Docker and copies it
  into the nodes with `kind load docker-image`. No registry is involved.
- **The database.** PostgreSQL 17 runs inside the cluster as a StatefulSet in the
  namespace `lab`, under the same Service name, `postgres`, that the app uses on AKS.
- **Cleanup.** `make kind-down` deletes the cluster and the lab's local records for it.
- **Tests.** The repo's end-to-end test (`tests/e2e-kind.sh`) runs on a kind cluster.

What each path gives you:

| | kind (Path A) | AKS (Path B) |
|---|---|---|
| Where it runs | Docker on your machine; free | Azure, East US; billable while it is up |
| Control plane | a container on your machine | managed by Azure |
| Nodes | one control-plane and one worker container | a system node pool and an autoscaled user node pool |
| Network | kindnet, inside Docker | a virtual network with network security groups; Azure CNI Overlay with Cilium |
| Database | PostgreSQL in the cluster | Azure Database for PostgreSQL behind a private endpoint, with private DNS |
| Image | built locally, loaded into the nodes | built in Azure Container Registry, pulled with the kubelet's managed identity |
| Sign-in | the admin kubeconfig kind writes | Entra ID with Azure RBAC, from authorized IP ranges only |
| Scenarios | 2 (five of its six faults) and 3 | 1, 2, 3 and 5 |

Scenario 4, a controller you write, runs anywhere (see the [scenario table](#scenarios)).

kind has no managed control plane, node pools, cluster autoscaler, private endpoint,
virtual network, network security group, Entra ID sign-in, managed identities or
container registry. That is why scenario 1 (an AKS upgrade) and scenario 5 (the cluster
autoscaler) need AKS. It is also why one of scenario 2's six faults, the Azure network
security group, is skipped on kind, so scenario 2 picks from the other five there.

The practice transfers: Deployments, Services, NetworkPolicies, probes, quotas and the
other Kubernetes API objects behave the same on both.

## Quick start

Pick one path. Each runs top to bottom, in order.

### Path A: local `kind` cluster (scenarios 2 and 3)

```bash
git clone https://github.com/davidshaevel-dot-com/davidshaevel-k8s-lab.git
cd davidshaevel-k8s-lab
make test                 # optional: unit tests and fault-machinery tests, no cluster needed
make kind-up              # one control-plane node + one worker, in Docker
make deploy               # builds the app image, loads it into kind, deploys app + PostgreSQL
make status               # should end with HEALTHY
                          # first time: do the warm-up now (see "Start with the warm-up"); it plants nothing
make plant SCENARIO=3     # plants one random fault; start your timer and work it
make reveal               # only after you have written down your diagnosis
make heal                 # restores the healthy state
make status               # HEALTHY again
make clear-events         # optional: clears the namespace's events before the next run
make kind-down            # when you are done
```

What runs on `kind`, and what needs AKS: see
[Two ways to run the lab](#two-ways-to-run-the-lab-kind-and-aks).

### Path B: AKS lab cluster (all scenarios)

This creates billable Azure resources. Run `make down` when you stop for the day.

```bash
git clone https://github.com/davidshaevel-dot-com/davidshaevel-k8s-lab.git
cd davidshaevel-k8s-lab
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
#   edit terraform/terraform.tfvars:
#     subscription_id                 = output of: az account show --query id -o tsv
#     api_server_authorized_ip_ranges = ["<output of: curl -4 -s https://ifconfig.me>/32"]
#     (-4 matters: AKS accepts IPv4 ranges only)
make up                   # terraform apply: type "yes" at the prompt (about 10-15 minutes)
make deploy               # builds the image in Azure Container Registry, deploys, creates the DB role
make status               # should end with HEALTHY
                          # first time: do the warm-up now (see "Start with the warm-up"); it plants nothing
make plant SCENARIO=2     # work it, write the cause down, then:
make reveal
make heal
make status
make clear-events         # optional: clears the namespace's events before the next run
make down                 # terraform destroy (type "yes"), at the end of the day
```

`make up` runs Terraform as your `az login` user. If your shell exports `ARM_CLIENT_ID` /
`ARM_CLIENT_SECRET` for a service principal, the lab ignores them on purpose: the
cluster-admin role assignment goes to whoever runs `apply`, and that must be you.

## Start with the warm-up

Once `make status` ends with `HEALTHY`, do the warm-up before any scenario:
[trace a healthy rollout](scenarios/0-warm-up-trace-a-rollout/exercise.md). You restart
the `web` Deployment yourself and follow the rollout from the change you submit to new
pods behind the Service, so you know what normal looks like and which part of Kubernetes
does each step. It plants nothing and works on both kind and AKS. Its walkthrough is
listed under "Review after your attempt".

## Challenge first, time yourself, then review

This routine is for the numbered scenarios. The warm-up skips it: it plants nothing and
has no timer and no `make reveal`. `make plant` is only for scenarios 2 and 3.

1. Run `make plant SCENARIO=<n>`. It prints the alert, nothing else. Start a timer.
2. Diagnose from the cluster: `kubectl get`, `describe`, `logs`, `events`, `exec`, the
   Azure CLI. Off limits during the attempt, because they are answer keys, not diagnosis:
   - the `faults/` directory and the walkthroughs;
   - `.lab/state`, `.lab/last-plant.log` and `.lab/last-heal.log`;
   - the shell tests in `tests/` (`*.sh`), which test the lab's own machinery;
   - diffing the live objects against this repo's manifests (`kubectl diff -k ...`);
   - `kubectl get --show-managed-fields`, which shows which tool changed which field;
   - the Azure portal's YAML and JSON views of objects in the lab, which show the same
     managed fields, and the portal's Copilot helpers (the "Troubleshoot" button, "Ask
     Copilot" and the YAML page's help prompts), which do the diagnosing for you. The
     portal's Overview, Pods, Replica sets, Events and Network policies pages remain fine.

   The passwords in `.lab/*-password` are fair game: they stand in for a secret store.
3. Fix it the way you would in production. (`make heal` is the reset button, not the fix.)
4. Write the cause down, stop the timer, then run `make reveal`.
5. Copy `runs/TEMPLATE.md` to `runs/YYYY-MM-DD-s<n>-<short-name>.md` and fill it in.
6. Read the walkthrough (below) and compare.
7. `make heal`, `make status`, and go again: each plant is a fresh draw. Optionally run
   `make clear-events` first: events stay in the namespace for about an hour, and the last
   run's would mix into the next run's `describe` output and event lists. This is a lab
   convenience: on a real cluster, events are evidence and are left alone.

### When something is off

- **Full reset.** `make heal` undoes every fault the lab knows about. If your own fix
  added something the manifests do not remove, or the `.lab/` directory was deleted,
  reset the app fully:
  `kubectl delete namespace lab && make deploy`.
- **Plant or heal failed.** Their output goes to `.lab/last-plant.log` and
  `.lab/last-heal.log`, base64-encoded so it cannot spoil a run; read them after
  `make reveal` (or when you give up) with `base64 -d < .lab/last-plant.log`.
- **`make down` stops at the node pool.** Terraform fails deleting the `user` node pool
  with `KubernetesAPICallFailed`: draining the node would evict a `web` pod against its
  disruption budget. It ends with `polling after Delete: context deadline exceeded`.
  `make down` removes the `lab` namespace first so this should be rare; if it happens,
  delete the pool without the budget check, then run `make down` again:
  `az aks nodepool delete --resource-group k8s-lab-rg --cluster-name k8s-lab-aks --name user --ignore-pdb`.
  The names come from the default prefix `k8s-lab`; use yours if you changed it, and add
  `--subscription <your subscription id>` if your `az` default is another subscription.
- **Database as admin.** `scripts/db-admin.sh "<SQL>"` runs one statement as the
  database admin and prints the result: on `kind`, with `psql` in the PostgreSQL pod; on
  AKS, from inside a web pod, the only place the private endpoint is reachable, with the
  admin password from Terraform output.

## Scenarios

| # | Scenario | Root-cause family | Key skills | Runs on |
|---|---|---|---|---|
| 0 | [Warm-up: trace a healthy rollout](scenarios/0-warm-up-trace-a-rollout/exercise.md) | None: nothing is planted | `rollout restart`, `rollout status`, events, ReplicaSets, `describe pod`, EndpointSlices | AKS, kind |
| 1 | AKS upgrade | Version skew, deprecated APIs, disruption budgets | `az aks get-upgrades`, surge settings, PDBs, control plane then node pools, runbook + recovery plan | AKS |
| 2 | The app can't reach its database | Networking and access: name resolution, Services and endpoints, NetworkPolicy, network security groups, credentials and ports, database-side access rules | CoreDNS, EndpointSlices, Cilium policy, NSG rules, Secrets, PostgreSQL errors | AKS (6 faults), kind (5) |
| 3 | The deployment never becomes ready | The rollout path: images, scheduling, probes, configuration, quotas, startup crashes | `rollout status`, ReplicaSets, events, `describe pod`, `logs --previous`, ResourceQuota | AKS, kind |
| 4 | Namespace guardrails controller | Drift: guardrail objects deleted by hand | Go, controller-runtime, reconcile loops, envtest | anywhere |
| 5 | Autoscaling under load | Capacity: pods, then nodes | HPA, cluster autoscaler, metrics, load generation | AKS |

Scenarios 1, 4 and 5 hold only their alert text so far; their content arrives in later work.

## What's in the repo

```
app/            labapp: a small Flask app; /api/visits reads and writes PostgreSQL
k8s/base/       Deployment (probes, requests), Service, default-deny NetworkPolicy + allow
                rules, PodDisruptionBudget, ResourceQuota, ConfigMap
k8s/overlays/   kind (in-cluster PostgreSQL) and aks (private endpoint) variants
kind/           kind cluster config
terraform/      the AKS lab cluster and everything around it
scripts/        what the Makefile targets run
faults/         the planted faults (spoilers)
docs/           reference pages: kubectl and the Azure portal, side by side
scenarios/      one folder per scenario: scenario.txt (the alert) and walkthrough.md;
                the warm-up (0) has exercise.md in place of scenario.txt
runs/           run logs, one per attempt, and their templates
tests/          shell tests for the fault machinery, and the kind end-to-end run
```

What the app is and how it runs: [app/README.md](app/README.md).

## The AKS lab cluster

- **Network.** Its own resource group (`k8s-lab-rg`) and VNet in East US. Node subnet and
  private-endpoint subnet each have a network security group. Azure CNI Overlay with
  Cilium as the network data plane and NetworkPolicy engine.
- **Nodes.** A system pool (1 x Standard_D2s_v5, critical add-ons only) and a user pool
  (Standard_D2s_v5, autoscaling 1 to 3). Sized against the subscription's East US quota.
- **Version.** Kubernetes created one minor version behind the newest AKS offers (1.36.5
  while 1.37.1 is newest) so scenario 1 has an upgrade to do. The version is a variable
  in `terraform/variables.tf`; after creation Terraform ignores it, so a later `make up`
  never undoes the upgrade you did by hand. A new cluster after `make down` starts at the
  variable's value again.
- **Identity.** OIDC issuer and workload identity are enabled.
- **Database.** Azure Database for PostgreSQL Flexible Server, reached only through a
  private endpoint in the lab VNet with a `privatelink.postgres.database.azure.com`
  private DNS zone. The server itself lives in Central US (`postgres_location`), because
  new Flexible Servers are restricted in East US for this subscription. The app reaches
  it as the in-cluster Service `postgres`, the same name it uses on `kind`.
- **Images.** Azure Container Registry (Basic). `make deploy` builds the image there
  (`az acr build`), which needs no local Docker. Some subscription offers do not allow
  ACR Tasks; if `az acr build` fails, `make deploy` builds locally with Docker
  (`linux/amd64`, pushed with `az acr login`) instead, and tells you to start Docker
  Desktop if it is not running. `LAB_IMAGE_BUILD=local make deploy` skips straight to the
  local build.
- **Names.** The registry is `k8sdevlabacr` and the PostgreSQL server `k8s-lab-pg`. Both
  names are unique across all of Azure, and these are taken by this lab, so if you run it
  in your own subscription, set `acr_name` and `postgres_server_name` in
  `terraform.tfvars` (the example file shows both). On AKS the image is
  `<registry>.azurecr.io/davidshaevel-k8s-lab/labapp:0.1.0`.
- **Changing those names on a running lab.** A new registry or server name replaces that
  resource, so never apply the change over a running lab. Run `make down` before you pull
  it, then `make up` and `make deploy` after. (The names changed once, from a random
  suffix to the ones above.)
- **State.** Terraform state is local and gitignored. It holds the database admin
  password; never commit it.

Where each Kubernetes object and Azure resource of the lab shows up in the Azure portal,
next to the `kubectl` or `az` command that shows it: [docs/azure-portal.md](docs/azure-portal.md).

### Access: the break-glass route

The API server accepts connections only from the CIDRs in
`api_server_authorized_ip_ranges` (your IP). Sign-in is through Entra ID with Azure RBAC
for Kubernetes, and the cluster's local admin account is disabled, so there is no
certificate-based kubeconfig to leak. `make up` fetches an Entra ID kubeconfig and
converts it with `kubelogin` to reuse your `az login` session, so `kubectl` and every
`make` target run without a browser prompt per command. This direct, IP-restricted,
Entra-authenticated path is the break-glass route. A Teleport agent may join the cluster
later as the everyday route; this path stays.

If your IP changes, update `terraform.tfvars` and run `make up` again (Terraform updates
the authorized ranges in place).

### Address ranges

| Range | Lab | Platform cluster (for reference) |
|---|---|---|
| VNet | 10.100.0.0/16 | 10.224.0.0/12 |
| Pods (overlay) | 10.120.0.0/16 | 10.244.0.0/16 |
| Services | 10.130.0.0/16 | 10.0.0.0/16 |

None of the lab's ranges overlaps another or the platform cluster's, so the two VNets
can be peered later (for example to manage and monitor the lab from the platform)
without renumbering. They are variables with these defaults.

### Cost

AKS control plane on the Free tier; two to four Standard_D2s_v5 nodes; a Burstable B1ms
PostgreSQL; ACR Basic; a standard load balancer and a private endpoint. All of it goes away
with `make down`.

## Review after your attempt

Spoilers. Open these only after you have written down your diagnosis.

- [Warm-up walkthrough](scenarios/0-warm-up-trace-a-rollout/walkthrough.md) (after the
  warm-up; it holds no scenario spoilers)
- [Scenario 1 walkthrough](scenarios/1-aks-upgrade/walkthrough.md)
- [Scenario 2 walkthrough](scenarios/2-app-cannot-reach-database/walkthrough.md)
- [Scenario 3 walkthrough](scenarios/3-deployment-never-ready/walkthrough.md)
- [Scenario 4 walkthrough](scenarios/4-namespace-guardrails-controller/walkthrough.md)
- [Scenario 5 walkthrough](scenarios/5-autoscaling-under-load/walkthrough.md)
