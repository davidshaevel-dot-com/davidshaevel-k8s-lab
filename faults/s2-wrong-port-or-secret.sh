# The app connects with a wrong port or a wrong password (one of the two, at random).
fault_supports() { return 0; }
fault_describe() { echo "Wrong port or secret: either DB_PORT in ConfigMap web-config became 5433, or DB_PASSWORD in Secret web-db no longer matches the database (see variant)."; }
fault_plant() {
  if [ $((RANDOM % 2)) -eq 0 ]; then
    state_set variant "port: DB_PORT=5433 in ConfigMap web-config"
    set_config DB_PORT 5433
  else
    state_set variant "secret: DB_PASSWORD in Secret web-db was replaced"
    apply_secret web-db DB_USER=labapp DB_PASSWORD="$(openssl rand -hex 16)"
  fi
  restart_web
}
fault_heal() {
  set_config DB_PORT 5432
  ensure_app_secrets
  restart_web
}
