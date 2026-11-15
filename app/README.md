# labapp

labapp is the workload the lab runs: a small Python web app (Flask, served by gunicorn)
that counts visits in a PostgreSQL table. It is deliberately simple, so that what you
look at during a scenario is Kubernetes and Azure, not application logic. It still has
what a real service has: probes, resource requests, a Service, NetworkPolicies, a
database behind a private network path, and credentials in a Secret. That gives every
scenario something real to deploy, route to and connect through.

For how the scenarios work, see
[Challenge first, time yourself, then review](../README.md#challenge-first-time-yourself-then-review)
in the root README. This page describes the app as it runs when it is healthy.

## Endpoints

The app listens on port 8080. Every response is JSON.

| Method and path | Returns | Uses the database |
|---|---|---|
| `GET /healthz` | `{"status": "ok"}` | no |
| `GET /readyz` | `{"status": "ready"}` | no |
| `GET /` | `{"app": "labapp", "version": "0.1.0", "hostname": "<pod name>"}` | no |
| `GET /api/visits` | `{"count": <rows in the visits table>}` | yes: reads |
| `POST /api/visits` | `{"count": <new count>}` after inserting one row | yes: writes, then reads |

- **Liveness** (`/healthz`) and **readiness** (`/readyz`) both test only that a gunicorn
  worker answers HTTP. Neither opens a database connection. A pod is Ready when the
  process serves requests, whether or not the database is reachable at that moment.
- **`GET /`** shows which pod answered: `hostname` is the pod's name. Requests sent to
  the Service from inside the cluster are spread across both replicas. A
  `kubectl port-forward` to the Service picks one pod when it starts and sends
  everything to that pod.
- **`/api/visits`** opens a new database connection for each request (autocommit), runs
  its query and closes it. If the database call raises an error, both methods return
  HTTP 503 with `{"error": "database unavailable", "detail": "<the driver's message>"}`
  and log the same message.
- **The table** is `visits (id BIGSERIAL PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT now())`.
  Before each query the app checks whether it exists and creates it only if it does not.
  On AKS, `make deploy` creates it ahead of time.

## How a request travels

```
client (another pod, `kubectl port-forward`, or `kubectl exec` inside a web pod)
  │
  ▼
Service web (namespace lab, ClusterIP, port 80) ──► a Ready web pod, port 8080
                                                       gunicorn, 2 workers
  │  the app connects to DB_HOST=postgres, port 5432
  ▼
name resolution: cluster DNS (kube-dns in kube-system)
  resolves postgres.lab.svc.cluster.local to the ClusterIP of Service postgres
  │
  ├─ kind: Service postgres selects the pod of StatefulSet postgres
  │        (PostgreSQL 17 in the cluster, port 5432)
  │
  └─ AKS:  Service postgres has no selector. Its EndpointSlice postgres-1 holds one
           address: the private endpoint's IP in the private-endpoint subnet
           (10.100.8.0/24). The private endpoint leads to Azure Database for
           PostgreSQL Flexible Server, which has no public access.
```

The namespace starts from a default-deny NetworkPolicy, so each hop above has an
explicit allow rule; see [Kubernetes objects](#kubernetes-objects).

## Configuration

The app reads its configuration from environment variables once, at startup. gunicorn
runs with `--preload`, so the app is built in the master process before the workers
fork. `DB_HOST`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` are required and have no
default. `DB_PORT` and `DB_CONNECT_TIMEOUT` must be whole numbers.

| Variable | Value in the lab | Where it comes from | Default in the code |
|---|---|---|---|
| `DB_HOST` | `postgres` | ConfigMap `web-config` | none (required) |
| `DB_PORT` | `5432` | ConfigMap `web-config` | `5432` |
| `DB_NAME` | `labapp` | ConfigMap `web-config` | none (required) |
| `DB_CONNECT_TIMEOUT` | `3` (seconds) | ConfigMap `web-config` | `3` |
| `DB_SSLMODE` | `disable` on kind, `require` on AKS | ConfigMap `web-config`: the base says `prefer`; each overlay replaces it | `prefer` |
| `DB_USER` | `labapp` | Secret `web-db`, written by `make deploy` | none (required) |
| `DB_PASSWORD` | a random 32-character hex string | Secret `web-db`, written by `make deploy` | none (required) |

The Deployment loads both with `envFrom` (the ConfigMap first, then the Secret).
`sslmode=require` encrypts the connection but does not verify the server's certificate.

**Database role and password.** The app always connects as the role `labapp` to the
database `labapp`. The first `make deploy` on each environment generates the password
with `openssl rand -hex 16` and keeps it in a gitignored file in your clone, which
stands in for a secret store. Later deploys reuse it.

- **On kind,** `labapp` is the role the PostgreSQL image creates at first start
  (`POSTGRES_USER`), so it owns the database. The StatefulSet reads the same username
  and password from the Secret `postgres-auth`, which `make deploy` also writes.
- **On AKS,** Terraform creates the Flexible Server with a separate admin login.
  `make deploy` signs in as that admin from inside a web pod, because the private
  endpoint can only be reached from the VNet. It then creates or updates the following:
  - the `labapp` role (LOGIN, with the generated password)
  - the `labapp` database and its `visits` table
  - grants of `CONNECT` on the database, `SELECT, INSERT` on `visits`, and `USAGE` on
    the sequence `visits_id_seq`

  The app itself never uses the admin login.

## How it is built and deployed

The image is `labapp:0.1.0`, built from [Dockerfile](Dockerfile):

- base image `python:3.12-slim`;
- the pinned packages in `requirements.txt` (Flask, gunicorn, psycopg);
- the command `gunicorn --preload --bind 0.0.0.0:8080 --workers 2 --access-logfile - labapp.wsgi:app`;
- runs as uid 10001, a non-root user.

`make deploy` runs [scripts/deploy.sh](../scripts/deploy.sh) against the current lab
cluster (`kind-k8s-lab` or `k8s-lab-aks`). It does these steps in order:

1. **Builds the image.**
   - On kind: `docker build -t labapp:0.1.0 app`, then
     `kind load docker-image --name k8s-lab labapp:0.1.0`, so the nodes have the image
     without a registry.
   - On AKS: `az acr build` builds and stores the image in the lab's Azure Container
     Registry, with no local Docker needed. If ACR Tasks is not available on the
     subscription, it falls back to a local `docker buildx build --platform linux/amd64`
     and pushes the image after `az acr login`. `LAB_IMAGE_BUILD=local make deploy` goes
     straight to the local build.
2. **Writes a generated kustomize overlay** (gitignored) on top of `k8s/overlays/kind` or
   `k8s/overlays/aks`. On AKS it fills in three values from Terraform output:
   - the image name in the registry;
   - the private endpoint's IP in the EndpointSlice `postgres-1`;
   - the private-endpoint subnet in the NetworkPolicy `db-egress`.
3. **Applies the namespace** `lab` with server-side apply.
4. **Writes the Secrets:** `web-db`, and on kind also `postgres-auth`.
5. **Applies the overlay** with server-side apply: the base manifests plus the
   environment's overlay.
6. **Waits** for the StatefulSet `postgres` on kind, then for the Deployment `web`, up to
   180 seconds each.
7. **Sets up the database role** on AKS only: it creates or updates the role, database,
   table and grants described above, and retries once after 30 seconds if the first try
   fails.

### Kubernetes objects

Everything lives in the namespace `lab`.

| Object | Name | Details |
|---|---|---|
| Namespace | `lab` | Pod Security admission: `enforce: baseline`, `warn: restricted` |
| ConfigMap | `web-config` | the five non-secret variables above |
| Secret | `web-db` | `DB_USER`, `DB_PASSWORD` (written by `make deploy`, not stored in the repo) |
| Deployment | `web` | details in the list below this table |
| Service | `web` | ClusterIP, port 80 to the container port `http` (8080), selects `app.kubernetes.io/name: web` |
| PodDisruptionBudget | `web` | `minAvailable: 1` |
| ResourceQuota | `lab-quota` | `pods: 10`, `requests.cpu: 1`, `requests.memory: 1Gi`, `limits.memory: 2Gi` |
| NetworkPolicy | `default-deny` | every pod in `lab`, ingress and egress: nothing is allowed unless another policy allows it |
| NetworkPolicy | `allow-dns` | every pod may reach the `kube-dns` pods in `kube-system` on UDP and TCP 53 |
| NetworkPolicy | `web-ingress` | web pods accept TCP 8080 from any namespace |
| NetworkPolicy | `db-egress` | pods labelled `lab.davidshaevel.com/db-client: "true"` may connect on TCP 5432: on kind to the `postgres` pods, on AKS to the private-endpoint subnet (`10.100.8.0/24`) |
| NetworkPolicy | `postgres-ingress` | kind only: the `postgres` pods accept TCP 5432 from the db-client pods |
| StatefulSet | `postgres` | kind only: one replica of `postgres:17-alpine`, runs as uid 70, data on an `emptyDir` (it starts empty whenever the pod is recreated), requests 100m CPU and 128Mi memory, memory limit 512Mi, readiness by `pg_isready` |
| Service | `postgres` | kind: selects the `postgres` pod. AKS: no selector |
| Secret | `postgres-auth` | kind only: the database's own username and password |
| EndpointSlice | `postgres-1` | AKS only: the private endpoint's IP, port 5432, owned by Service `postgres` |

The Deployment `web`:

- **Replicas and rollout:** 2 replicas; `RollingUpdate` with `maxSurge: 1` and
  `maxUnavailable: 0`; `progressDeadlineSeconds: 120`; `revisionHistoryLimit: 0`.
- **Pod labels:** `app.kubernetes.io/name: web` and `lab.davidshaevel.com/db-client: "true"`.
- **Container:** `web`, image `labapp:0.1.0` (the registry copy on AKS), port 8080 named
  `http`.
- **Resources:** requests 50m CPU and 96Mi memory; memory limit 256Mi; no CPU limit.
- **Probes:** liveness `GET /healthz` every 10s, failing after 3 misses; readiness
  `GET /readyz` every 5s, failing after 2 misses.
- **Security:** runs as uid 10001 with `runAsNonRoot` and the `RuntimeDefault` seccomp
  profile; no privilege escalation; all capabilities dropped; read-only root
  filesystem, with an `emptyDir` mounted at `/tmp`.

## How to check it

Run these after `make deploy` has finished (see the root README's quick start). The
`kubectl` commands use your current context, which `make kind-up` or `make up` set to
the lab cluster.

```bash
make status
```

`make status` lists the Deployments, StatefulSets and pods in `lab`, then runs four
checks:

1. the `web` rollout is complete;
2. the Service `web` has ready endpoints;
3. `GET /readyz`, sent from inside a Ready web pod, returns 200;
4. `POST /api/visits`, sent from inside a Ready web pod, returns 200. This writes one row
   and reads the count back.

It prints `HEALTHY` when all four pass. Otherwise it prints `UNHEALTHY (<n> check(s) failed)`
and exits non-zero. HEALTHY means the app is serving and has a working path to PostgreSQL,
with read and write access.

To reach the app yourself, forward a local port to the Service and leave it running:

```bash
kubectl -n lab port-forward svc/web 8080:80
```

Then, in a second terminal:

```bash
curl -s http://localhost:8080/
curl -s http://localhost:8080/api/visits
curl -s -X POST http://localhost:8080/api/visits
```

Or, without a port-forward, from inside a web pod:

```bash
kubectl -n lab exec deploy/web -c web -- python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:8080/api/visits').read().decode())"
```

The app's logs are gunicorn's access log plus the app's own messages:
`kubectl -n lab logs deploy/web`.

## Tests

The app's tests need no cluster and no database. From the root of the repository:

```bash
make test
```

That command does three things:

- creates `.venv` if it does not exist and installs `app/requirements-dev.txt` into it;
- runs the app's tests with pytest;
- runs the lab's shell tests.

To run only the app's tests:

```bash
python3 -m venv .venv
.venv/bin/pip install -r app/requirements-dev.txt
cd app && ../.venv/bin/pytest -q
```

| Test file | What it covers |
|---|---|
| `tests/test_app.py` | every endpoint, using an in-memory store in place of PostgreSQL: health and readiness answer even when the store fails; `GET /` identifies the app; `GET` and `POST /api/visits` return the count; a store error becomes a 503 with `error` and `detail` |
| `tests/test_config.py` | required variables, defaults, overrides, integer parsing, and that the connection string carries every setting |
| `tests/test_factory.py` | `build_app` wires in the PostgreSQL store without connecting, and rejects invalid configuration before serving |
| `tests/test_store_integration.py` | the real store against a real PostgreSQL. Skipped unless you set `LABAPP_TEST_DB_HOST`, `LABAPP_TEST_DB_NAME`, `LABAPP_TEST_DB_USER` and `LABAPP_TEST_DB_PASSWORD` (optionally also `LABAPP_TEST_DB_PORT`, `LABAPP_TEST_DB_SSLMODE`); the names mirror the `DB_*` variables |

## Files

| Path | What it is |
|---|---|
| `app/labapp/__init__.py` | the app version (`0.1.0`) |
| `app/labapp/app.py` | the endpoints (`create_app`); the store is passed in, so tests can replace it |
| `app/labapp/config.py` | reads and validates the `DB_*` variables; builds the connection string |
| `app/labapp/store.py` | `PostgresStore`: the `visits` table, one connection per request (psycopg 3) |
| `app/labapp/factory.py` | `build_app`: configuration, then store, then app |
| `app/labapp/wsgi.py` | gunicorn's entry point (`labapp.wsgi:app`); sets up logging |
| `app/Dockerfile` | the image |
| `app/requirements.txt`, `app/requirements-dev.txt` | pinned runtime packages; adds pytest for tests |
| `app/pytest.ini`, `app/tests/` | test configuration and the tests above |
| `k8s/base/` | Namespace, ConfigMap, Deployment, Service, NetworkPolicies, PodDisruptionBudget, ResourceQuota |
| `k8s/overlays/kind/` | in-cluster PostgreSQL (StatefulSet, Service), its NetworkPolicies, `DB_SSLMODE=disable` |
| `k8s/overlays/aks/` | the selectorless Service and EndpointSlice for the private endpoint, `db-egress` by subnet, `DB_SSLMODE=require` |
| `scripts/deploy.sh` | what `make deploy` runs |
| `scripts/status.sh` | what `make status` runs |
