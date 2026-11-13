# davidshaevel-k8s-lab - Agent Context

## Project Overview

A public, hands-on Kubernetes practice lab. Agents build the scenarios and plant the
faults; David works each scenario himself on a real cluster (a throwaway AKS cluster, or a
local `kind` cluster for the troubleshooting scenarios) and writes the run logs.

**Key Technologies:**
- **Infrastructure:** Terraform (azurerm), Kubernetes, kustomize, kind
- **Cloud:** Azure (AKS, PostgreSQL Flexible Server, ACR, private endpoints)
- **Languages:** Python (the lab app), Bash (lab scripts, fault scripts), HCL

**Project Management:**
- **Issue Tracking:** Linear (Team Tacocat), project "Kubernetes Lab Practice"
- **Version Control:** GitHub (public repository)
- **Branching Strategy:** Feature branches with PR workflow

---

## Hard rules for agents

- **Never create, change or delete an Azure resource.** No `terraform apply`, no
  `terraform destroy`, no `az ... create|update|delete`, no `make up|down|plant|heal`
  against AKS. `terraform fmt`, `terraform validate`, `terraform plan` and read-only `az`
  reads (`list`, `show`, `get-versions`) are fine. David applies.
- **The repository is public.** Never name an employer, a hiring contact or a job
  application, and never commit a subscription id, tenant id, password or kubeconfig.
  Values like these live in the gitignored `terraform/terraform.tfvars`, `.envrc` and
  `AGENTS.local.md`.
- **Walkthroughs are spoilers.** The README links them only under the "Review after your
  attempt" heading. Never quote a walkthrough, a fault id or a fault description in
  README text above that heading, in `scenario.txt`, or in anything `make plant` prints.
- **Run logs in `runs/` are David's.** Agents never write or edit a run log (the template
  is the exception).

---

## Architecture

```
                 David's IP only (authorized IP ranges)
                 Entra ID sign-in (kubelogin), local admin disabled
                                   │
 ┌─ resource group: <prefix>-rg (East US) ─────────────────────────────────────┐
 │  VNet 10.40.0.0/16                                                          │
 │   ├─ snet-aks-nodes 10.40.0.0/22  (NSG) ── AKS: system pool + user pool     │
 │   │                                         Azure CNI Overlay, Cilium       │
 │   │                                         pods 192.168.0.0/16 (overlay)   │
 │   └─ snet-private-endpoints 10.40.8.0/24 (NSG) ── private endpoint ──┐      │
 │                                                                       ▼      │
 │  Private DNS zone privatelink.postgres.database.azure.com   PostgreSQL       │
 │  ACR (Basic) ── AcrPull ── kubelet identity                 Flexible Server  │
 └─────────────────────────────────────────────────────────────────────────────┘

 Namespace `lab`: Deployment `web` (labapp) → Service `postgres` → database
   - AKS:  `postgres` is a selectorless Service + EndpointSlice → private endpoint IP
   - kind: `postgres` selects an in-cluster PostgreSQL StatefulSet
```

---

## Repository Structure

```
davidshaevel-k8s-lab/
├── .bare/                     # Bare git repository
├── main/                      # Main branch worktree
│   ├── README.md              # Quick start, scenario table, honesty line
│   ├── Makefile               # up, down, kind-up, kind-down, deploy, plant, reveal, heal, status, test, check
│   ├── app/                   # labapp: Flask + psycopg, Dockerfile, pytest tests
│   ├── k8s/base/              # Namespace, Deployment, Service, NetworkPolicies, PDB, ResourceQuota
│   ├── k8s/overlays/{kind,aks}/
│   ├── kind/cluster.yaml      # kind cluster config
│   ├── terraform/             # AKS lab cluster, VNet, NSGs, PostgreSQL + private endpoint, ACR
│   ├── scripts/               # Bash behind the Makefile targets (lib.sh holds shared helpers)
│   ├── faults/                # One file per planted fault: plant/heal/supports functions
│   ├── scenarios/<n>-<name>/  # scenario.txt (alert) + walkthrough.md (read after the attempt)
│   ├── runs/                  # David's run logs + TEMPLATE.md
│   └── tests/                 # Shell tests for the fault machinery
└── <feature-worktrees>/       # Flat
```

---

## Important File Locations

- `scripts/lib.sh` — environment detection (kind vs aks), lab state in `.lab/`, logging.
- `faults/*.sh` — each defines `fault_supports`, `fault_plant`, `fault_heal`; the
  scenario number is the filename prefix (`s2-`, `s3-`).
- `.lab/` — gitignored local state (planted fault, generated kind database password).
- `terraform/terraform.tfvars.example` — copy to `terraform.tfvars` (gitignored).

---

## Helpful Commands

```bash
make test          # pytest for the app + shell tests that need no cluster
make check         # test + terraform fmt -check + terraform validate
make kind-up deploy status
make plant SCENARIO=2 ; make reveal ; make heal
LAB_FAULT=<id> make plant SCENARIO=3   # forced fault, for testing only (keep out of README)
```

---

## Environment Variables

Environment-specific values are stored in `.envrc` (gitignored). A committed
`.envrc.example` documents them. All are optional; the defaults work.

| Variable | Used By | Purpose |
|----------|---------|---------|
| `LAB_ENV` | scripts | Force `kind` or `aks` instead of detecting from the kube context |
| `KIND_CLUSTER_NAME` | scripts | kind cluster name (default `k8s-lab`) |
| `LAB_FAULT` | plant.sh | Testing hook: plant this fault id instead of a random one |

---

## References

- **Linear Project:** Kubernetes Lab Practice (Team Tacocat)
- **AKS docs:** https://learn.microsoft.com/azure/aks/

---

## Private policy

Operator-private rules live in `AGENTS.local.md` beside this file (gitignored).
Harnesses with import support load it here: @AGENTS.local.md
Otherwise: if `AGENTS.local.md` exists, read it before acting; if not, continue without it.
