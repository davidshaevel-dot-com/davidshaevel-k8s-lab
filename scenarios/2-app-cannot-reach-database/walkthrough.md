# Scenario 2 walkthrough: the app can't reach its database

Read this only after your attempt and after `make reveal`.

## The method

The request path is: web pod → name resolution (`postgres`) → Service `postgres` →
endpoints → NetworkPolicy (egress from the pod, ingress to the database pod on `kind`) →
on AKS, the node subnet's network security group → private endpoint → PostgreSQL, which
then checks the role, the password and its own access rules.

Work it from the app outward. The error text tells you which layer to look at first:

| What the app says (`detail` in the 503) | Layer it points at |
|---|---|
| `Name or service not known` | name resolution |
| `connection timeout expired` | something drops packets: NetworkPolicy, NSG, a Service with no endpoints (Cilium drops), a port nothing listens on |
| `Connection refused` | something answers with a reset: no endpoints (kube-proxy rejects), wrong port on a reachable host |
| `password authentication failed` | credentials |
| `pg_hba.conf rejects connection`, `permission denied for database` | the database's own access rules |

Useful first moves:

```bash
kubectl -n lab get pods,svc,endpointslices,networkpolicies
kubectl -n lab logs deploy/web --tail=20
kubectl -n lab exec deploy/web -- env | grep ^DB_
kubectl -n lab exec deploy/web -- python -c "import socket; print(socket.getaddrinfo('postgres', 5432))"
kubectl -n lab get events --sort-by=.lastTimestamp | tail -20
```

## Fault: name resolution (`s2-dns`)

- **Symptom.** `Name or service not known`. Pods are Ready and were restarted recently.
- **Trail.** `env | grep DB_HOST` in the pod shows `postgresql`. `getaddrinfo('postgres')`
  works, `getaddrinfo('postgresql')` fails. `kubectl -n lab get configmap web-config -o yaml`
  shows the source.
- **Cause.** `DB_HOST` in ConfigMap `web-config` was changed to a Service name that does
  not exist, and the Deployment was restarted to pick it up.
- **Fix.** Set `DB_HOST: postgres` in the ConfigMap (in Git, then apply) and
  `kubectl -n lab rollout restart deploy/web`. ConfigMap changes do not reach running pods'
  environment variables without a restart.
- **Production habit.** Hash config into the pod template (kustomize `configMapGenerator`
  does this) so a config change is a visible rollout, not a silent restart.

## Fault: Service with no endpoints (`s2-no-endpoints`)

- **Symptom.** `connection timeout expired` (Cilium, and kindnet here, drop) or
  `Connection refused` (kube-proxy in iptables mode rejects). DNS resolves `postgres` to
  a ClusterIP.
- **Trail.** `kubectl -n lab get endpointslices -l kubernetes.io/service-name=postgres`
  is empty. On `kind`: `kubectl -n lab get svc postgres -o jsonpath='{.spec.selector}'`
  shows `app.kubernetes.io/name: postgresql`, and
  `kubectl -n lab get pods --show-labels` shows the database pod is labelled `postgres`.
  On AKS the Service has no selector by design; its EndpointSlice `postgres-1` carries the
  label `kubernetes.io/service-name: postgres-primary`, so no Service owns it.
- **Cause.** The Service's selector (kind) or the EndpointSlice's owning label (AKS) no
  longer matches.
- **Fix.** Correct the selector, or relabel the EndpointSlice
  `kubernetes.io/service-name=postgres`.
- **Production habit.** "Service exists but has no endpoints" is the first thing to check
  for any in-cluster connection failure: `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`.

## Fault: NetworkPolicy (`s2-netpol`)

- **Symptom.** `connection timeout expired`. DNS works, endpoints exist.
- **Trail.** `kubectl -n lab get networkpolicies`; `default-deny` blocks all egress, so
  something must allow 5432. `kubectl -n lab get networkpolicy db-egress -o yaml` allows
  TCP **5433**. On AKS, `hubble observe --namespace lab --verdict DROPPED` (if you have the
  Hubble CLI) shows the drops with the policy verdict.
- **Cause.** The allow rule for database egress names the wrong port.
- **Fix.** Port 5432 in `db-egress`.
- **Production habit.** With default-deny, every new dependency needs an allow rule;
  read policies as "what is allowed", because a NetworkPolicy never denies by itself.

## Fault: network security group (`s2-nsg`, AKS only)

- **Symptom.** `connection timeout expired`. Everything inside Kubernetes looks right:
  DNS, endpoints, NetworkPolicy.
- **Trail.** The packet leaves the node, so look at Azure.
  `az network nsg rule list -g k8s-lab-rg --nsg-name k8s-lab-nodes-nsg -o table` shows
  `Outbound-Policy-120`, priority 120, Deny, TCP, destination 10.100.8.0/24, port 5432.
  Network Watcher can confirm: `az network watcher test-ip-flow` with the node's NIC, or
  check effective rules: `az network nic list-effective-nsg`.
- **Cause.** A deny rule on the node subnet's NSG blocks the nodes from the private
  endpoint subnet. With Azure CNI Overlay, pod traffic leaves the node with the node's
  IP, so the node subnet's rules apply to every pod.
- **Fix.** Delete the rule (or fix it in Terraform, which is the source of truth).
- **Production habit.** When Kubernetes-level checks all pass and packets still vanish,
  move one layer down: NSGs, route tables, firewalls, private DNS.

## Fault: wrong port or secret (`s2-wrong-port-or-secret`)

`make reveal` says which variant you had.

- **Port variant.** `connection timeout expired` (or refused). `env | grep DB_PORT` shows
  5433; the Service only exposes 5432. Fix `DB_PORT` in `web-config` and restart.
- **Secret variant.** `password authentication failed for user "labapp"`. The network is
  fine: the server answered. `kubectl -n lab get secret web-db -o jsonpath='{.data.DB_PASSWORD}' | base64 -d`
  differs from what the database expects. Restore the right password in the Secret and
  restart. The lab keeps the right one in `.lab/kind-db-password` or `.lab/aks-db-password`,
  its stand-in for a secret store (on `kind`, the database's own Secret `postgres-auth`
  also has it).
- **Production habit.** An authentication error proves the network path works; stop
  looking at the network.

## Fault: database-side access rule (`s2-db-firewall`)

- **Symptom, `kind`.** `pg_hba.conf rejects connection for host "10.244.x.y"`. The server
  answered, and refused.
  **Trail.** `kubectl -n lab exec statefulset/postgres -- sh -c 'head -3 $PGDATA/pg_hba.conf'`:
  the first line rejects the whole pod network, and PostgreSQL uses the first matching
  line.
  **Fix.** Remove the line and reload: `SELECT pg_reload_conf();`.
- **Symptom, AKS.** `permission denied for database "labapp"` / `User does not have
  CONNECT privilege`. The Azure Flexible Server firewall applies only to public access,
  and this server has none, so on AKS the database-side rule is a privilege:
  `CONNECT` on database `labapp` was revoked from the app role.
  **Trail.** As the admin, through a web pod (the only place the private endpoint is
  reachable): `scripts/db-admin.sh "SELECT datname, datacl FROM pg_database"`. The
  `labapp` database's ACL has no `labapp=c` and no `=c` (PUBLIC) entry.
  **Fix.** `scripts/db-admin.sh "GRANT CONNECT ON DATABASE labapp TO labapp"`.
- **Production habit.** Read the server's error message literally: `pg_hba` and
  `privilege` errors are configuration on the database, not on the network.
