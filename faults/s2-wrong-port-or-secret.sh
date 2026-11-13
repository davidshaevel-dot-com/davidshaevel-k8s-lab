# The app connects with a wrong port or a wrong password (one of the two, at random).
fault_supports() { return 0; }
fault_describe() { echo "Wrong port or secret: either DB_PORT in ConfigMap web-config became 5433, or DB_PASSWORD in Secret web-db no longer matches the database (see variant)."; }
fault_plant() {
  local pick=$((RANDOM % 2))
  case "${LAB_FAULT_VARIANT:-}" in port) pick=0 ;; secret) pick=1 ;; esac # testing hook
  if [ "$pick" -eq 0 ]; then
    state_set variant "port: DB_PORT=5433 in ConfigMap web-config"
    set_config DB_PORT 5433
  else
    state_set variant "secret: DB_PASSWORD in Secret web-db was replaced"
    apply_secret web-db DB_USER=labapp DB_PASSWORD="$(openssl rand -hex 16)"
  fi
  restart_web
}
fault_heal() {
  # Restart only if something was actually wrong: heal runs for every fault.
  local before after
  before=$(k get configmap web-config -o jsonpath='{.data.DB_PORT}'; k get secret web-db -o jsonpath='{.data.DB_PASSWORD}')
  set_config DB_PORT 5432
  ensure_app_secrets
  after=$(k get configmap web-config -o jsonpath='{.data.DB_PORT}'; k get secret web-db -o jsonpath='{.data.DB_PASSWORD}')
  [ "$before" = "$after" ] || restart_web
}
