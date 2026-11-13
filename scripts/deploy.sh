#!/usr/bin/env bash
# make deploy: build the app image, write the secrets, apply the manifests and
# wait for the app. `--apply-only` skips the image build (used by make heal).
. "$(dirname "$0")/lib.sh"

apply_only=false
[ "${1:-}" = --apply-only ] && apply_only=true
need kubectl
env_name=$(lab_env)
overlay_dir="$LAB_STATE_DIR/overlay"

build_image() {
  case "$env_name" in
    kind)
      need docker; need kind
      info "Building $APP_IMAGE_NAME:$APP_IMAGE_TAG and loading it into kind"
      docker build -q -t "$APP_IMAGE_NAME:$APP_IMAGE_TAG" "$LAB_ROOT/app" >/dev/null
      kind load docker-image --name "$KIND_CLUSTER_NAME" "$APP_IMAGE_NAME:$APP_IMAGE_TAG" >/dev/null
      ;;
    aks)
      need az; need terraform
      info "Building $APP_IMAGE_NAME:$APP_IMAGE_TAG in Azure Container Registry $(tf_out acr_name)"
      az acr build --registry "$(tf_out acr_name)" --image "$APP_IMAGE_NAME:$APP_IMAGE_TAG" --no-logs --output none "$LAB_ROOT/app"
      ;;
  esac
}

# The generated overlay (gitignored) adds the values only known at deploy time.
render_overlay() {
  mkdir -p "$overlay_dir"
  local base
  base=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$LAB_ROOT/k8s/overlays/$env_name" "$overlay_dir")
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    echo "  - $base"
    if [ "$env_name" = aks ]; then
      cat <<YAML
images:
  - name: $APP_IMAGE_NAME
    newName: $(tf_out acr_login_server)/$APP_IMAGE_NAME
    newTag: "$APP_IMAGE_TAG"
patches:
  - target: {kind: EndpointSlice, name: postgres-1}
    patch: |-
      - op: replace
        path: /endpoints/0/addresses/0
        value: "$(tf_out postgres_private_ip)"
  - target: {kind: NetworkPolicy, name: db-egress}
    patch: |-
      - op: replace
        path: /spec/egress/0/to/0/ipBlock/cidr
        value: "$(tf_out private_endpoint_subnet_cidr)"
YAML
    fi
  } > "$overlay_dir/kustomization.yaml"
}

# On AKS the app role, database and table are created by the admin, through a web pod.
init_database() {
  local pw
  pw=$(lab_password aks-db)
  info "Creating the app's database role and table"
  db_admin "$(python3 -c 'import json,sys; pw=sys.argv[1]; print(json.dumps([
    {"db": "postgres", "sql": "CREATE ROLE labapp LOGIN PASSWORD {}", "params": [pw],
     "unless": "SELECT 1 FROM pg_roles WHERE rolname = '"'"'labapp'"'"'"},
    {"db": "postgres", "sql": "ALTER ROLE labapp LOGIN PASSWORD {}", "params": [pw]},
    {"db": "postgres", "sql": "CREATE DATABASE labapp",
     "unless": "SELECT 1 FROM pg_database WHERE datname = '"'"'labapp'"'"'"},
    {"db": "labapp", "sql": "CREATE TABLE IF NOT EXISTS visits (id BIGSERIAL PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT now())"},
    {"db": "labapp", "sql": "GRANT CONNECT ON DATABASE labapp TO labapp"},
    {"db": "labapp", "sql": "GRANT SELECT, INSERT ON visits TO labapp"},
    {"db": "labapp", "sql": "GRANT USAGE ON SEQUENCE visits_id_seq TO labapp"}]))' "$pw")"
}

$apply_only || build_image
render_overlay
info "Applying manifests ($env_name)"
kc apply -f "$LAB_ROOT/k8s/base/namespace.yaml" >/dev/null
ensure_app_secrets >/dev/null
kc apply -k "$overlay_dir" >/dev/null
if [ "$env_name" = kind ]; then
  k rollout status statefulset/postgres --timeout=180s >/dev/null || die "PostgreSQL did not become ready"
fi
k rollout status deployment/web --timeout=180s >/dev/null || die "the web Deployment did not become ready"
if [ "$env_name" = aks ] && ! $apply_only; then init_database; fi
info "Deployed. Check with: make status"
