# Shared helpers for the lab scripts. Source it; do not run it.
set -euo pipefail

LAB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LAB_STATE_DIR=${LAB_STATE_DIR:-$LAB_ROOT/.lab}
LAB_NS=lab
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-k8s-lab}
KIND_CONTEXT="kind-$KIND_CLUSTER_NAME"
AKS_CONTEXT=k8s-lab-aks
APP_IMAGE_NAME=labapp
APP_IMAGE_TAG=0.1.0
TF_DIR="$LAB_ROOT/terraform"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed (see the README prerequisites)"; }

# lab_env prints kind or aks. Order: LAB_ENV, then the current kube context if it
# is a lab context, then the environment recorded by the last kind-up / up.
# It never guesses: an unrelated context (another cluster) is an error.
lab_env() {
  if [ -n "${LAB_ENV:-}" ]; then
    case "$LAB_ENV" in kind | aks) echo "$LAB_ENV"; return ;; *) die "LAB_ENV must be kind or aks" ;; esac
  fi
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  case "$ctx" in
    "$KIND_CONTEXT") echo kind; return ;;
    "$AKS_CONTEXT") echo aks; return ;;
  esac
  if [ -f "$LAB_STATE_DIR/env" ]; then cat "$LAB_STATE_DIR/env"; return; fi
  die "no lab cluster found (current context '${ctx:-none}'); run 'make kind-up' or 'make up' first"
}

lab_context() {
  case "$(lab_env)" in kind) echo "$KIND_CONTEXT" ;; aks) echo "$AKS_CONTEXT" ;; esac
}

# k runs kubectl against the lab cluster and namespace only, whatever the
# current context is, so the lab can never touch another cluster.
k() { kubectl --context "$(lab_context)" -n "$LAB_NS" "$@"; }
kc() { kubectl --context "$(lab_context)" "$@"; } # cluster-scoped, no namespace

# tf runs terraform as the `az login` user. ARM_* service-principal variables in
# the shell are ignored on purpose: the cluster-admin role assignment goes to
# whoever runs apply, and that must be the person using the lab.
tf() {
  env -u ARM_CLIENT_ID -u ARM_CLIENT_SECRET -u ARM_CLIENT_CERTIFICATE_PATH \
    -u ARM_USE_MSI -u ARM_USE_OIDC -u ARM_OIDC_TOKEN terraform -chdir="$TF_DIR" "$@"
}
# tf_out fails loudly: callers assign it to a variable first (a failing $(...)
# inside a heredoc would not stop the script).
tf_out() {
  local v
  v=$(tf output -raw "$1") && [ -n "$v" ] || die "terraform output '$1' is empty; run 'make up' from this checkout first"
  printf '%s' "$v"
}
# az_sub runs az against the subscription Terraform uses, not the CLI default.
az_sub() { az "$@" --subscription "$(tf_out subscription_id)"; }

# --- planted-fault state -------------------------------------------------------
# One file, base64-encoded so a glance (or a stray `cat`) does not spoil the run.
STATE_FILE="$LAB_STATE_DIR/state"

state_exists() { [ -s "$STATE_FILE" ]; }
state_read() { base64 -d < "$STATE_FILE" 2>/dev/null || base64 -D < "$STATE_FILE"; }
state_get() { state_exists && state_read | sed -n "s/^$1=//p" | head -1; }
state_set() { # key value
  mkdir -p "$LAB_STATE_DIR"
  local current=""
  state_exists && current=$(state_read | grep -v "^$1=" || true)
  printf '%s\n%s=%s\n' "$current" "$1" "$2" | grep -v '^$' | base64 > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}
state_clear() { rm -f "$STATE_FILE"; }

scenario_dir() { # n -> scenarios/<n>-<name>
  local d
  for d in "$LAB_ROOT"/scenarios/"$1"-*/; do [ -d "$d" ] && { echo "${d%/}"; return; }; done
  return 1
}

# fault_files <scenario> <env>: fault files for that scenario that support env.
fault_files() {
  local f
  for f in "$LAB_ROOT"/faults/s"$1"-*.sh; do
    [ -f "$f" ] || continue
    if (. "$f"; fault_supports "$2"); then echo "$f"; fi
  done
}

# --- app config, secrets and database helpers (used by deploy and the faults) ---

restart_web() { k rollout restart deployment/web; }
set_config() { k patch configmap web-config --type merge -p "{\"data\":{\"$1\":\"$2\"}}"; }

# A password generated once per environment and kept in .lab/ (gitignored),
# which stands in for a secret store. If the file is gone (say, git clean -fdx),
# kind recovers it from the database's own Secret instead of generating a new
# one the running database would not accept. (On AKS, deploy and heal re-set
# the role's password to this value, so a new one is harmless there.)
lab_password() { # name
  local f="$LAB_STATE_DIR/$1-password" existing=""
  mkdir -p "$LAB_STATE_DIR"
  if [ ! -s "$f" ] && [ "$1" = kind-db ]; then
    existing=$(k get secret postgres-auth -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  fi
  if [ ! -s "$f" ]; then
    (umask 077; if [ -n "$existing" ]; then printf '%s\n' "$existing"; else openssl rand -hex 16; fi > "$f")
  fi
  cat "$f"
}

# apply_secret <name> <key=value>...
apply_secret() {
  local name=$1; shift
  local args=() kv
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  k create secret generic "$name" "${args[@]}" --dry-run=client -o yaml | k apply --server-side --force-conflicts -f -
}

# ensure_app_secrets writes the healthy secrets for the current environment.
ensure_app_secrets() {
  local pw
  case "$(lab_env)" in
    kind)
      pw=$(lab_password kind-db)
      apply_secret postgres-auth username=labapp password="$pw"
      apply_secret web-db DB_USER=labapp DB_PASSWORD="$pw"
      ;;
    aks)
      pw=$(lab_password aks-db)
      apply_secret web-db DB_USER=labapp DB_PASSWORD="$pw"
      ;;
  esac
}

ready_web_pod() {
  k get pods -l app.kubernetes.io/name=web \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' |
    awk '$2 == "True" && !found { print $1; found = 1 }'
}

# pg_exec runs a shell command in the kind PostgreSQL pod.
pg_exec() { k exec statefulset/postgres -c postgres -- sh -c "$1"; }

# db_admin runs SQL steps against Azure PostgreSQL as the admin, from inside a
# ready web pod (the only place the private endpoint is reachable). It connects
# by the server's FQDN, which resolves through the private DNS zone to the
# private endpoint. Credentials travel in environment variables and on stdin,
# never on a command line. Steps are JSON:
#   [{"db": "postgres", "sql": "CREATE ROLE {} ...", "params": ["..."], "unless": "SELECT ..."}]
DB_ADMIN_PY='
import json, sys, psycopg
from psycopg import sql
d = json.load(sys.stdin)
for step in d["steps"]:
    with psycopg.connect(host=d["host"], port=5432, dbname=step["db"], user=d["user"],
                         password=d["password"], sslmode="require", connect_timeout=10,
                         autocommit=True) as conn:
        if step.get("unless") and conn.execute(step["unless"]).fetchone():
            continue
        conn.execute(sql.SQL(step["sql"]).format(*[sql.Literal(p) for p in step.get("params", [])]))
'
db_admin() { # steps-json
  local pod host user password
  pod=$(ready_web_pod)
  [ -n "$pod" ] || die "no ready web pod to reach the database through"
  host=$(tf_out postgres_fqdn)
  user=$(tf_out postgres_admin_login)
  password=$(tf_out postgres_admin_password)
  DB_HOST_="$host" DB_USER_="$user" DB_PASSWORD_="$password" DB_STEPS_="$1" python3 -c '
import json, os
print(json.dumps({"host": os.environ["DB_HOST_"], "user": os.environ["DB_USER_"],
                  "password": os.environ["DB_PASSWORD_"], "steps": json.loads(os.environ["DB_STEPS_"])}))' |
    k exec -i "$pod" -c web -- python -c "$DB_ADMIN_PY"
}
