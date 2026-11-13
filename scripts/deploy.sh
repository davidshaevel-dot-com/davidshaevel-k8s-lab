#!/usr/bin/env bash
# make deploy: build the app image, write the secrets, apply the manifests and
# wait for the app. `--apply-only` skips the image build (used by make heal).
. "$(dirname "$0")/lib.sh"

apply_only=false
[ "${1:-}" = --apply-only ] && apply_only=true
need kubectl
env_name=$(lab_env)
overlay_dir="$LAB_STATE_DIR/overlay"

# AKS image build. ACR Tasks (`az acr build`) first: it needs no local Docker.
# Some subscription offers do not allow ACR Tasks (TasksOperationsNotAllowed);
# then build locally and push. LAB_IMAGE_BUILD=local skips straight to that.
build_image_aks() {
  local acr login_server image
  acr=$(tf_out acr_name)
  login_server=$(tf_out acr_login_server)
  image="$login_server/$APP_IMAGE_NAME:$APP_IMAGE_TAG"
  if [ "${LAB_IMAGE_BUILD:-}" != local ]; then
    info "Building $APP_IMAGE_NAME:$APP_IMAGE_TAG in Azure Container Registry $acr (az acr build)"
    if az_sub acr build --registry "$acr" --image "$APP_IMAGE_NAME:$APP_IMAGE_TAG" --no-logs --output none "$LAB_ROOT/app"; then
      return 0
    fi
    info "az acr build failed (ACR Tasks may not be allowed on this subscription); building locally with Docker instead"
  fi
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 ||
    die "cannot build the image: az acr build failed and Docker is not running. Start Docker Desktop and run 'make deploy' again (or run it with LAB_IMAGE_BUILD=local)."
  az_sub acr login --name "$acr" >/dev/null
  # linux/amd64: AKS nodes are amd64, and Apple Silicon builds arm64 by default.
  docker buildx build --platform linux/amd64 -t "$image" --push "$LAB_ROOT/app" ||
    die "local image build or push failed; see the output above"
}

build_image() {
  case "$env_name" in
    kind)
      need docker; need kind
      info "Building $APP_IMAGE_NAME:$APP_IMAGE_TAG and loading it into kind"
      docker build -q -t "$APP_IMAGE_NAME:$APP_IMAGE_TAG" "$LAB_ROOT/app" >/dev/null
      kind load docker-image --name "$KIND_CLUSTER_NAME" "$APP_IMAGE_NAME:$APP_IMAGE_TAG" >/dev/null 2>&1
      ;;
    aks)
      need az; need terraform
      build_image_aks
      ;;
  esac
}

# The generated overlay (gitignored) adds the values only known at deploy time.
# Every value is read before anything is written: a failed `terraform output`
# must stop the deploy, not render an overlay with empty fields.
render_overlay() {
  local base login_server pe_ip pe_cidr
  base=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$LAB_ROOT/k8s/overlays/$env_name" "$overlay_dir")
  if [ "$env_name" = aks ]; then
    login_server=$(tf_out acr_login_server)
    pe_ip=$(tf_out postgres_private_ip)
    pe_cidr=$(tf_out private_endpoint_subnet_cidr)
  fi
  mkdir -p "$overlay_dir"
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    echo "  - $base"
    if [ "$env_name" = aks ]; then
      cat <<YAML
images:
  - name: $APP_IMAGE_NAME
    newName: $login_server/$APP_IMAGE_NAME
    newTag: "$APP_IMAGE_TAG"
patches:
  - target: {kind: EndpointSlice, name: postgres-1}
    patch: |-
      - op: replace
        path: /endpoints/0/addresses/0
        value: "$pe_ip"
  - target: {kind: NetworkPolicy, name: db-egress}
    patch: |-
      - op: replace
        path: /spec/egress/0/to/0/ipBlock/cidr
        value: "$pe_cidr"
YAML
    fi
  } > "$overlay_dir/kustomization.yaml"
}

# On AKS the app role, database and table are created by the admin, through a
# web pod. Idempotent; heal runs it too, which re-syncs the role's password
# with .lab/ and restores its CONNECT privilege.
init_database() {
  local pw
  pw=$(lab_password aks-db)
  info "Creating or re-syncing the app's database role and table" >&2
  db_admin "$(APP_PW_="$pw" python3 -c 'import json, os; pw = os.environ["APP_PW_"]; print(json.dumps([
    {"db": "postgres", "sql": "CREATE ROLE labapp LOGIN PASSWORD {}", "params": [pw],
     "unless": "SELECT 1 FROM pg_roles WHERE rolname = '"'"'labapp'"'"'"},
    {"db": "postgres", "sql": "ALTER ROLE labapp LOGIN PASSWORD {}", "params": [pw]},
    {"db": "postgres", "sql": "CREATE DATABASE labapp",
     "unless": "SELECT 1 FROM pg_database WHERE datname = '"'"'labapp'"'"'"},
    {"db": "labapp", "sql": "CREATE TABLE IF NOT EXISTS visits (id BIGSERIAL PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT now())"},
    {"db": "labapp", "sql": "GRANT CONNECT ON DATABASE labapp TO labapp"},
    {"db": "labapp", "sql": "GRANT SELECT, INSERT ON visits TO labapp"},
    {"db": "labapp", "sql": "GRANT USAGE ON SEQUENCE visits_id_seq TO labapp"}]))')"
}

# Server-side apply writes no kubectl.kubernetes.io/last-applied-configuration
# annotation, so `kubectl get -o yaml` on a faulted object shows only the live
# (faulted) value. Objects first applied client-side get the annotation removed.
apply_ss() { kc apply --server-side --force-conflicts "$@"; }
strip_last_applied() {
  kc annotate namespace "$LAB_NS" kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
  k annotate deployment,statefulset,service,configmap,secret,networkpolicy,poddisruptionbudget,resourcequota,endpointslice \
    --all kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
}

$apply_only || build_image
render_overlay
info "Applying manifests ($env_name)"
apply_ss -f "$LAB_ROOT/k8s/base/namespace.yaml" >/dev/null
ensure_app_secrets >/dev/null
apply_ss -k "$overlay_dir" >/dev/null
strip_last_applied
if [ "$env_name" = kind ]; then
  k rollout status statefulset/postgres --timeout=180s >/dev/null || die "PostgreSQL did not become ready"
fi
k rollout status deployment/web --timeout=180s >/dev/null || die "the web Deployment did not become ready"
if [ "$env_name" = aks ]; then
  # One retry: just after the NSG fault is healed, the path can take a moment.
  init_database >/dev/null || { info "database re-sync failed; retrying in 30s"; sleep 30; init_database >/dev/null; }
fi
info "Deployed. Check with: make status"
