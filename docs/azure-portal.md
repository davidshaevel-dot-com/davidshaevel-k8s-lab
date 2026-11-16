# kubectl and the Azure portal, side by side

This page maps the whole AKS lab: each Kubernetes object and each Azure resource the
lab creates, with the `kubectl` or `az` command that shows it and where the same
information is in the Azure portal. Use it to connect what a command prints with what
the portal shows.

- **AKS only.** The local `kind` cluster has no Azure portal. On kind, use the `kubectl`
  commands.
- **`kubectl` first.** The portal is another client of the same Kubernetes API that
  `kubectl` talks to. When the two disagree, read the object with `kubectl`.
- **Look, do not edit.** Do not change objects in the portal. The lab's state comes from
  the manifests, `make deploy` and `make heal`, and a change made by hand is not undone
  by them. That includes the YAML page's Review + save button.
- **During a scenario attempt,** the portal's YAML and JSON views and its Copilot helpers
  are off limits; see "Challenge first" in the [README](../README.md).
- **Labels change.** Portal labels change over time. The labels on this page were read
  on 2026-11-15: the "Kubernetes resources" menu, the Workloads page, and a
  Deployment's Overview, YAML, Events and Live logs pages were read from the portal
  itself. The
  other paths follow Microsoft's documentation. If a label differs, go by the portal.

## Getting to the cluster

Resource groups → `k8s-lab-rg` → `k8s-lab-aks` (type Kubernetes service). Its left menu
has a group, "Kubernetes resources", with these items: Namespaces; Workloads; Services,
gateways and ingresses; Network policies; Storage; Configuration; Custom resources;
Events; Run command; Helm (preview).

These pages read the cluster through its API server with your Entra ID sign-in, the
same way `kubectl` does. The API server accepts only the authorized IP ranges, so they
work from the same network as your `kubectl`.

**Workloads** has tabs for Deployments, Pods, Replica sets, Stateful sets, Daemon sets,
Jobs and Cron jobs. Set "Filter by namespace" to `lab` to see only the lab's objects.
Refresh reloads the list, and Show labels adds each object's labels.

**Run command** runs `kubectl` commands against the cluster from the portal. It is one
more client of the same API.

## A Deployment's page

Workloads → Deployments → `web` opens a page with a left menu of Overview, YAML, Events
and Live logs.

**Overview.** The "Essentials" section lists Namespace, Ready, Revision history,
Strategy type, Labels, Selector, Cluster, Creation time, Min ready seconds, Replicas and
Rolling update strategy. For `web`, Replicas reads "2 desired, 2 updated, 2 total,
2 available, 0 unavailable", and Rolling update strategy reads "0 max unavailable,
1 max surge". "See more" adds Annotations, including `deployment.kubernetes.io/revision`.
Below the Essentials come an Events summary (Total, Warning and Normal counts),
Resource utilization, Application performance metrics, and Workloads with two tabs:

- **Pods:** Pod name, Ready, Status, Restart count, Age, CPU, Memory, Node, Pod IP and
  Labels.
- **Replica sets:** "Current replica set" and "Old replica sets", each with Name, Ready,
  Current, Age, Images and Labels.

Where the cluster's monitoring add-on is off, the CPU column shows "Enable metrics". The
lab does not need it.

**One reading that did not match.** On 2026-11-15, Essentials showed
"Revision history : 10", while
`kubectl -n lab get deploy web -o jsonpath='{.spec.revisionHistoryLimit}'` printed `0`
and "Old replica sets" was empty. The `kubectl` value is the one the Deployment
controller uses. This is the rule of thumb above in practice.

**YAML.** Tabs YAML and JSON, and buttons Review + save, Dry-run and Discard. It shows
the object as the API server stores it, including `managedFields`. Do not edit objects
here.

**Events.** The events for `web` from the Kubernetes API, with Refresh and Download
buttons, filters for Timeframe, Type, Reason, Source, Object and Namespace (one hour, and
namespace `lab`, by default), and a message search box. The columns are Message, Type,
Reason, Source, Count and Last seen. A rollout of `web` appears as `ScalingReplicaSet`
rows from `deployment-controller`, with messages like "Scaled up replica set web-… from
0 to 1". "Last seen" is an absolute time in UTC (for example `2026-11-16T00:59:22Z` is
18:59:22 US Central on 2026-11-15), where `kubectl get events` shows a relative age
such as `2m`. The page also offers Azure Monitor ("Enable historical logs" and a
Configure banner); the lab does not need it.

**Live logs.** Streams one pod's logs at a time: gunicorn's access log plus the app's
own messages. Pick the pod in the "Select a Pod" dropdown; there is a Search box, the
text "N item(s). Streaming logs", and Pause and Scroll buttons. The columns are
Timestamp, Pod, Container ID and Log content. The `kubectl` equivalent is
`kubectl -n lab logs -f <pod name>`. The Timestamp column is in your browser's local
time (for example `11/15/2026, 7:59:39 PM`), while an access-log line carries its own
time in UTC (`[16/Nov/2026:01:59:39 +0000]`). A banner offers Azure Monitor for
historical logs in Log Analytics; the lab does not need it.

## Kubernetes objects

All objects are in namespace `lab` unless the row says otherwise. Paths start from
`k8s-lab-aks` → Kubernetes resources.

| What you want to see | `kubectl` | Azure portal |
|---|---|---|
| The namespace `lab` | `kubectl get namespace lab --show-labels` | Namespaces → `lab` |
| The Deployment `web`: replicas, strategy, conditions | `kubectl -n lab describe deployment web` | Workloads → Deployments → `web` → Overview |
| The Deployment as stored, YAML | `kubectl -n lab get deployment web -o yaml` | Workloads → Deployments → `web` → YAML |
| ReplicaSets, current and old | `kubectl -n lab get rs -o wide` | Workloads → Replica sets; or `web` → Overview → Workloads → Replica sets |
| Pods: status, node, IP | `kubectl -n lab get pods -o wide` | Workloads → Pods; or `web` → Overview → Workloads → Pods |
| One pod in detail | `kubectl -n lab describe pod <pod>` | Workloads → Pods → the pod → Overview |
| Events in the namespace | `kubectl -n lab get events` | Events, filtered to namespace `lab` |
| Events for the Deployment | `kubectl -n lab describe deployment web` (bottom) | Workloads → Deployments → `web` → Events |
| Events for one pod | `kubectl -n lab describe pod <pod>` (bottom) | Workloads → Pods → the pod → Events |
| Logs, streamed, one pod at a time | `kubectl -n lab logs -f <pod name>` | Workloads → Deployments → `web` → Live logs → Select a Pod |
| Services `web` and `postgres` | `kubectl -n lab get services -o wide` | Services, gateways and ingresses → the Service |
| EndpointSlices behind each Service | `kubectl -n lab get endpointslices` | No page for EndpointSlices in the Kubernetes resources menu; use `kubectl` |
| The ConfigMap `web-config` | `kubectl -n lab get configmap web-config -o yaml` | Configuration → Config maps → `web-config` |
| The Secret `web-db` | `kubectl -n lab get secret web-db` | Configuration → Secrets → `web-db` |
| NetworkPolicies | `kubectl -n lab get networkpolicies` | Network policies, filtered to namespace `lab` |
| The ResourceQuota `lab-quota` and its usage | `kubectl -n lab describe resourcequota lab-quota` | No page for quotas in the Kubernetes resources menu; use `kubectl` |
| The PodDisruptionBudget `web` | `kubectl -n lab get pdb web` | No page for disruption budgets in the Kubernetes resources menu; use `kubectl` |
| Nodes (cluster-wide) | `kubectl get nodes -o wide` | `k8s-lab-aks` → Settings → Node pools → Nodes tab |
| Node pools `system` and `user` (Azure) | `az aks nodepool list -g k8s-lab-rg --cluster-name k8s-lab-aks -o table` | `k8s-lab-aks` → Settings → Node pools |

## Azure resources

Everything here is in the resource group `k8s-lab-rg`, except the infrastructure
resource group in the second row. The PostgreSQL server is in Central US; everything
else is in East US. The registry's name ends in a generated suffix; print it with
`terraform -chdir=terraform output -raw acr_name`.

| What you want to see | `az` | Azure portal |
|---|---|---|
| The lab's resource group and everything in it | `az resource list -g k8s-lab-rg -o table` | Resource groups → `k8s-lab-rg` → Overview |
| The infrastructure resource group that AKS manages (node scale sets, load balancer, its public IP, the kubelet's identity) | `az aks show -g k8s-lab-rg -n k8s-lab-aks --query nodeResourceGroup -o tsv` | `k8s-lab-aks` → Overview → Essentials → Infrastructure resource group |
| The cluster | `az aks show -g k8s-lab-rg -n k8s-lab-aks -o table` | `k8s-lab-rg` → `k8s-lab-aks` → Overview |
| The virtual network and its two subnets | `az network vnet subnet list -g k8s-lab-rg --vnet-name k8s-lab-vnet -o table` | `k8s-lab-rg` → `k8s-lab-vnet` → Settings → Subnets |
| The node subnet's network security group | `az network nsg rule list -g k8s-lab-rg --nsg-name k8s-lab-nodes-nsg --include-default -o table` | `k8s-lab-rg` → `k8s-lab-nodes-nsg` → Settings → Inbound security rules and Outbound security rules |
| The private-endpoint subnet's network security group | `az network nsg rule list -g k8s-lab-rg --nsg-name k8s-lab-pe-nsg --include-default -o table` | `k8s-lab-rg` → `k8s-lab-pe-nsg` → Settings → Inbound security rules and Outbound security rules |
| The private endpoint for PostgreSQL | `az network private-endpoint show -g k8s-lab-rg -n k8s-lab-pg-pe -o table` | `k8s-lab-rg` → `k8s-lab-pg-pe` → Overview; Settings → DNS configuration |
| The private DNS zone and its records | `az network private-dns record-set a list -g k8s-lab-rg -z privatelink.postgres.database.azure.com -o table` | `k8s-lab-rg` → `privatelink.postgres.database.azure.com` → record sets |
| The private DNS zone's link to the VNet | `az network private-dns link vnet list -g k8s-lab-rg -z privatelink.postgres.database.azure.com -o table` | `privatelink.postgres.database.azure.com` → Virtual network links |
| The PostgreSQL server | `az postgres flexible-server list -g k8s-lab-rg -o table` | `k8s-lab-rg` → the server whose name starts with `k8s-lab-pg` → Overview; Settings → Networking, Databases, Server parameters |
| The container registry | `az acr show -g k8s-lab-rg -n <registry> -o table` | `k8s-lab-rg` → the container registry → Overview |
| The registry's repositories and the app image's tags | `az acr repository list -n <registry> -o table`, then `az acr repository show-tags -n <registry> --repository <repository> -o table` | the container registry → Services → Repositories → the repository |
