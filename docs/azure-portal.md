# kubectl and the Azure portal, side by side

This page maps the whole AKS lab: each Kubernetes object and each Azure resource the
lab creates, with the `kubectl` or `az` command that shows it and where the same
information is in the Azure portal. Use it to connect what a command prints with what
the portal shows.

- **AKS only.** The local `kind` cluster has no Azure portal. On kind, use the `kubectl`
  commands.
- **`kubectl` first.** The portal is another client of the same Kubernetes API that
  `kubectl` talks to. When the two disagree, read the object with `kubectl`.
- **Look, do not edit.** Do not change anything in the portal. The lab's Kubernetes
  objects come from the manifests through `make deploy` and `make heal`, and its Azure
  resources come from Terraform through `make up`. A change made by hand bypasses both.
  That includes the YAML page's Review + save button. Some resource pages are live forms
  with Save and Discard buttons, for example the PostgreSQL server's Networking page.
  Viewing them is fine, but changing a setting there changes the lab outside Terraform.
- **Leave the command bar alone.** Opening an object from a list also ticks the
  checkbox on its row, which arms the list's command bar (Delete, Scale and the like).
  Opening an object does nothing else.
- **During a scenario attempt,** the portal's YAML and JSON views and its Copilot helpers
  (the "Troubleshoot" button, "Ask Copilot", the suggestion chips) are off limits; see
  "Challenge first" in the [README](../README.md). Every row below gives a way to read
  the same information without them.
- **Labels change.** Portal labels change over time. The labels on this page were read
  from the live portal on 2026-11-15. The few pages that were not read are listed at
  the end, under "Not observed yet". If a label differs, go by the portal.

## Getting to the cluster

Resource groups → `k8s-lab-rg` → `k8s-lab-aks` (type Kubernetes service). Its left menu
has a group, "Kubernetes resources", with these items: Namespaces; Workloads; Services,
gateways and ingresses; Network policies; Storage; Configuration; Custom resources;
Events; Run command; Helm (preview). Node pools and Properties are in the "Settings"
group of the same menu.

These pages read the cluster through its API server with your Entra ID sign-in, the
same way `kubectl` does. The API server accepts only the authorized IP ranges, so they
work from the same network as your `kubectl`.

**Workloads** has tabs for Deployments, Pods, Replica sets, Stateful sets, Daemon sets,
Jobs and Cron jobs. Choose `lab` in "Filter by namespace" to see only the lab's objects.
Refresh reloads the list, and Show labels adds each object's labels.

**Opening an object.** A pod, Service, network policy, ConfigMap or namespace opens on
its Overview page, with a small left menu: Overview, YAML and Events. A pod also has
Live logs.

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
buttons, a "Search for message..." box, and filters for Timeframe, Type, Reason,
Source, Object and Namespace. Timeframe stays at one hour unless Azure Monitor is
enabled. The columns are Message, Type, Reason, Source, Count and Last seen. A rollout
of `web` appears as `ScalingReplicaSet` rows from `deployment-controller`, with messages
like "Scaled up replica set web-… from 0 to 1". "Last seen" is an absolute time in UTC
(for example `2026-11-16T00:59:22Z` is 18:59:22 US Central on 2026-11-15), where
`kubectl get events` shows a relative age such as `2m`. The page also offers Azure
Monitor ("Enable historical logs" and a Configure banner); the lab does not need it.

**Live logs.** Streams one pod's logs at a time: gunicorn's access log plus the app's
own messages. Pick the pod in the "Select a Pod" dropdown; you have to pick it even on a
pod's own Live logs page. There is a Search box, the text "N item(s). Streaming logs",
and Pause and Scroll buttons. The columns are Timestamp, Pod, Container ID and Log
content. The `kubectl` equivalent is `kubectl -n lab logs -f <pod name>`. The Timestamp
column is in your browser's local time (for example `11/15/2026, 7:59:39 PM`), while an
access-log line carries its own time in UTC (`[16/Nov/2026:01:59:39 +0000]`). A banner
offers Azure Monitor for historical logs in Log Analytics; the lab does not need it.

## Kubernetes objects

All objects are in namespace `lab` unless the row says otherwise. Paths start from
`k8s-lab-aks` → Kubernetes resources, except the last two rows, which are under
Settings.

| What you want to see | `kubectl` | Azure portal |
|---|---|---|
| The namespace `lab` | `kubectl get namespace lab --show-labels` | Namespaces → `lab` → Overview: Status, Labels, Annotations, and its Workloads |
| The Deployment `web`: replicas, strategy, conditions | `kubectl -n lab describe deployment web` | Workloads → Deployments → `web` → Overview |
| The Deployment as stored, YAML | `kubectl -n lab get deployment web -o yaml` | Workloads → Deployments → `web` → YAML |
| ReplicaSets, current and old | `kubectl -n lab get rs -o wide` | Workloads → Replica sets; or `web` → Overview → Workloads → Replica sets |
| Pods: status, node, IP | `kubectl -n lab get pods -o wide` | Workloads → Pods: Pod name, Namespace, Ready, Status, Restart count, Age, CPU, Memory, Node, Pod IP |
| One pod in detail | `kubectl -n lab describe pod <pod name>` | Workloads → Pods → the pod → Overview: Essentials (including Controlled by, Node and Pod IP), and Containers with tabs Containers, Volumes and Conditions |
| Events in the namespace | `kubectl -n lab get events` | Events, with the Namespace filter set to `lab`; this page adds Object and Namespace columns |
| Events for the Deployment | `kubectl -n lab describe deployment web` (bottom) | Workloads → Deployments → `web` → Events |
| Events for one pod | `kubectl -n lab describe pod <pod name>` (bottom) | Workloads → Pods → the pod → Events |
| Logs, streamed, one pod at a time | `kubectl -n lab logs -f <pod name>` | `web` → Live logs, or the pod → Live logs; then Select a Pod |
| Services `web` and `postgres` | `kubectl -n lab get services -o wide` | Services, gateways and ingresses → Services tab → the Service → Overview |
| The addresses behind a Service | `kubectl -n lab get endpointslices` | The Service → Overview → Ports tab (Endpoints column) and Pods tab. No page lists EndpointSlice objects; `CiliumEndpointSlice` under Custom resources is Cilium's own resource, not the same object |
| The ConfigMap `web-config` | `kubectl -n lab get configmap web-config -o yaml` | Configuration → Config maps → `web-config` → Overview → Data tab |
| The Secret `web-db` | `kubectl -n lab get secret web-db` | Configuration → Secrets: Name, Namespace, Type, Data, Age |
| NetworkPolicies: which pods, which directions | `kubectl -n lab get networkpolicies` | Network policies: Name, Namespace, Pod selector, Policy types, Age; a policy → Overview adds the pods it selects |
| A NetworkPolicy's rules | `kubectl -n lab describe networkpolicy <name>` | Use `kubectl`. The portal's Overview shows no rules |
| The ResourceQuota `lab-quota` and its usage | `kubectl -n lab describe resourcequota lab-quota` | No page lists ResourceQuotas; use `kubectl` |
| The PodDisruptionBudget `web` | `kubectl -n lab get pdb web` | No page lists PodDisruptionBudgets; use `kubectl` |
| Nodes (cluster-wide) | `kubectl get nodes -o wide` | Settings → Node pools → Nodes tab: Node, Status, CPU, Memory, Disk, Pods, Node pool, Kubernetes version |
| Node pools `system` and `user` (Azure) | `az aks nodepool list -g k8s-lab-rg --cluster-name k8s-lab-aks -o table` | Settings → Node pools → Node pools tab |

## Azure resources

Everything here is in the resource group `k8s-lab-rg`, except the infrastructure
resource group in the second row. The PostgreSQL server is in Central US; everything
else is in East US. The registry's name ends in a generated suffix; print it with
`terraform -chdir=terraform output -raw acr_name`.

| What you want to see | `az` | Azure portal |
|---|---|---|
| The lab's resource group and everything in it | `az resource list -g k8s-lab-rg -o table` | Resource groups → `k8s-lab-rg` → Overview |
| The infrastructure resource group that AKS manages (node scale sets, load balancer, its public IP, the kubelet's identity) | `az aks show -g k8s-lab-rg -n k8s-lab-aks --query nodeResourceGroup -o tsv` | `k8s-lab-aks` → Settings → Properties → Infrastructure resource group |
| The cluster | `az aks show -g k8s-lab-rg -n k8s-lab-aks -o table` | `k8s-lab-rg` → `k8s-lab-aks` → Overview |
| The virtual network and its two subnets | `az network vnet subnet list -g k8s-lab-rg --vnet-name k8s-lab-vnet -o table` | `k8s-lab-rg` → `k8s-lab-vnet` → Settings → Subnets, with a Security group column |
| The node subnet's network security group | `az network nsg rule list -g k8s-lab-rg --nsg-name k8s-lab-nodes-nsg --include-default -o table` | `k8s-lab-rg` → `k8s-lab-nodes-nsg` → Overview (inbound and outbound rules in one grid); or Settings → Inbound security rules and Outbound security rules; Help → Effective security rules |
| The private-endpoint subnet's network security group | `az network nsg rule list -g k8s-lab-rg --nsg-name k8s-lab-pe-nsg --include-default -o table` | `k8s-lab-rg` → `k8s-lab-pe-nsg` → the same pages as the node subnet's |
| The private endpoint for PostgreSQL | `az network private-endpoint show -g k8s-lab-rg -n k8s-lab-pg-pe -o table` | `k8s-lab-rg` → `k8s-lab-pg-pe` → Overview; Settings → DNS configuration |
| The private DNS zone's records | `az network private-dns record-set a list -g k8s-lab-rg -z privatelink.postgres.database.azure.com -o table` | `k8s-lab-rg` → `privatelink.postgres.database.azure.com` → DNS Management → Recordsets |
| The private DNS zone's link to the VNet | `az network private-dns link vnet list -g k8s-lab-rg -z privatelink.postgres.database.azure.com -o table` | `privatelink.postgres.database.azure.com` → DNS Management → Virtual Network Links |
| The PostgreSQL server | `az postgres flexible-server list -g k8s-lab-rg -o table` | `k8s-lab-rg` → the server whose name starts with `k8s-lab-pg` → Overview; Settings → Networking, Databases, Server parameters |
| The container registry | `az acr show -g k8s-lab-rg -n <registry> -o table` | `k8s-lab-rg` → the container registry → Overview |
| The registry's repositories and the app image's tags | `az acr repository list -n <registry> -o table`, then `az acr repository show-tags -n <registry> --repository <repository> -o table` | the container registry → Services → Repositories → the repository |

## Not observed yet

These pages or parts were not read on 2026-11-15. Their paths follow Microsoft's
documentation and the menus that were read.

- Opening a Secret (only the Secrets list was read).
- The Node pools page's Node Auto-provisioning tab.
- `k8s-lab-rg` → Overview: the list of resources.
- `k8s-lab-nodes-nsg` → Outbound security rules, read as its own page.
- `k8s-lab-pe-nsg` → Overview and Inbound security rules.
- Help → Effective security rules, past its menu label.
- The PostgreSQL server's Server parameters page, past its menu label.
- A repository's page in the container registry, with its tags (only the Repositories
  list was read).
- The `az` commands on this page, which were not run while it was written.
