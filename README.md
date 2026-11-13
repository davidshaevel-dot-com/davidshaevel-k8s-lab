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
| Python | 3.12 | `make test`, and the scripts use `python3` for small JSON chores |
| kubectl | 1.37.0 | everything |
| Docker Desktop (running) | 29.9.2 | the local `kind` path |
| kind | 0.33.0 | the local `kind` path |
| Azure CLI (`az`) | 2.90.0 | the AKS path |
| Terraform | 1.16.2 | the AKS path |
| kubelogin | untested: not installed on the build machine | the AKS path (Entra ID sign-in) |

On macOS: `brew install kubectl kind azure-cli terraform Azure/kubelogin/kubelogin`
(or `az aks install-cli` for kubectl + kubelogin), and Docker Desktop from docker.com.

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
make plant SCENARIO=3     # plants one random fault; start your timer and work it
make reveal               # only after you have written down your diagnosis
make heal                 # restores the healthy state
make status               # HEALTHY again
make kind-down            # when you are done
```

On `kind`, PostgreSQL runs inside the cluster. One of scenario 2's six faults (the Azure
network security group) needs Azure networking and is skipped there; scenario 2 picks from
the other five. Scenarios 1 and 5 need AKS.

### Path B: AKS lab cluster (all scenarios)

This creates billable Azure resources. Run `make down` when you stop for the day.

```bash
git clone https://github.com/davidshaevel-dot-com/davidshaevel-k8s-lab.git
cd davidshaevel-k8s-lab
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
#   edit terraform/terraform.tfvars:
#     subscription_id                 = output of: az account show --query id -o tsv
#     api_server_authorized_ip_ranges = ["<output of: curl -s https://ifconfig.me>/32"]
make up                   # terraform apply (about 10-15 minutes), then fetches credentials
make deploy               # builds the image in Azure Container Registry, deploys, creates the DB role
make status               # should end with HEALTHY
make plant SCENARIO=2     # work it, write the cause down, then:
make reveal
make heal
make status
make down                 # terraform destroy, at the end of the day
```

`make up` runs Terraform as your `az login` user. If your shell exports `ARM_CLIENT_ID` /
`ARM_CLIENT_SECRET` for a service principal, the lab ignores them on purpose: the
cluster-admin role assignment goes to whoever runs `apply`, and that must be you.

## Challenge first, time yourself, then review

1. Run `make plant SCENARIO=<n>`. It prints the alert, nothing else. Start a timer.
2. Diagnose from the cluster: `kubectl get`, `describe`, `logs`, `events`, `exec`, the
   Azure CLI. Off limits during the attempt: the `faults/` directory, the walkthroughs,
   the `.lab/` directory, and diffing the live objects against this repo's manifests
   (`kubectl diff -k ...`). Those are answer keys, not diagnosis.
3. Fix it the way you would in production. (`make heal` is the reset button, not the fix.)
4. Write the cause down, stop the timer, then run `make reveal`.
5. Copy `runs/TEMPLATE.md` to `runs/YYYY-MM-DD-s<n>-<short-name>.md` and fill it in.
6. Read the walkthrough (below) and compare.
7. `make heal`, `make status`, and go again: each plant is a fresh draw.

## Scenarios

| # | Scenario | Root-cause family | Key skills | Runs on |
|---|---|---|---|---|
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
scenarios/      one folder per scenario: scenario.txt (the alert) and walkthrough.md
runs/           run logs, one per attempt
tests/          shell tests for the fault machinery, and the kind end-to-end run
```

## The AKS lab cluster

- **Network.** Its own resource group (`k8s-lab-rg`) and VNet in East US. Node subnet and
  private-endpoint subnet each have a network security group. Azure CNI Overlay with
  Cilium as the network data plane and NetworkPolicy engine.
- **Nodes.** A system pool (1 x Standard_D2s_v5, critical add-ons only) and a user pool
  (Standard_D2s_v5, autoscaling 1 to 3). Sized against the subscription's East US quota.
- **Version.** Kubernetes pinned one minor version behind the newest AKS offers (1.36.5
  while 1.37.1 is newest) so scenario 1 has an upgrade to do. The version is a variable
  in `terraform/variables.tf`.
- **Identity.** OIDC issuer and workload identity are enabled.
- **Database.** Azure Database for PostgreSQL Flexible Server, reached only through a
  private endpoint in the lab VNet with a `privatelink.postgres.database.azure.com`
  private DNS zone. The server itself lives in Central US (`postgres_location`), because
  new Flexible Servers are restricted in East US for this subscription. The app reaches
  it as the in-cluster Service `postgres`, the same name it uses on `kind`.
- **Images.** Azure Container Registry (Basic). `make deploy` builds the image there
  (`az acr build`), so the AKS path needs no local Docker.
- **State.** Terraform state is local and gitignored. It holds the database admin
  password; never commit it.

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

- [Scenario 1 walkthrough](scenarios/1-aks-upgrade/walkthrough.md)
- [Scenario 2 walkthrough](scenarios/2-app-cannot-reach-database/walkthrough.md)
- [Scenario 3 walkthrough](scenarios/3-deployment-never-ready/walkthrough.md)
- [Scenario 4 walkthrough](scenarios/4-namespace-guardrails-controller/walkthrough.md)
- [Scenario 5 walkthrough](scenarios/5-autoscaling-under-load/walkthrough.md)
