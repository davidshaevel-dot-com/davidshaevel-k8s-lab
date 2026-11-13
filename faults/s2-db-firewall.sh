# The database server itself refuses the app.
fault_supports() { return 0; }
fault_describe() { echo "Database-side firewall: kind: a pg_hba.conf rule rejects connections from the pod network (10.244.0.0/16); AKS: CONNECT on database labapp was revoked from the app role (Azure firewall rules do not apply to private-endpoint traffic)."; }
HBA_LINE='host all all 10.244.0.0/16 reject'
fault_plant() {
  case "$(lab_env)" in
    kind) pg_exec "sed -i '1i $HBA_LINE' \"\$PGDATA/pg_hba.conf\" && psql -U \"\$POSTGRES_USER\" -d labapp -qc 'SELECT pg_reload_conf()'" ;;
    aks) db_admin '[{"db":"labapp","sql":"REVOKE CONNECT ON DATABASE labapp FROM PUBLIC"},{"db":"labapp","sql":"REVOKE CONNECT ON DATABASE labapp FROM labapp"}]' ;;
  esac
}
fault_heal() {
  [ "$(lab_env)" = kind ] || return 0
  pg_exec "sed -i '\\|^$HBA_LINE\$|d' \"\$PGDATA/pg_hba.conf\" && psql -U \"\$POSTGRES_USER\" -d labapp -qc 'SELECT pg_reload_conf()'" 2>/dev/null || true
}
fault_heal_after_apply() {
  [ "$(lab_env)" = aks ] || return 0
  db_admin '[{"db":"labapp","sql":"GRANT CONNECT ON DATABASE labapp TO PUBLIC"},{"db":"labapp","sql":"GRANT CONNECT ON DATABASE labapp TO labapp"}]'
}
