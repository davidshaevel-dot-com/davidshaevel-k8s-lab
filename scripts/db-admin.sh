#!/usr/bin/env bash
# scripts/db-admin.sh "<SQL>" [database]: run one SQL statement as the database
# admin and print the result. kind: psql in the PostgreSQL pod. AKS: from inside a
# web pod (the only place the private endpoint is reachable), as the Terraform-
# created admin, with the password passed on stdin.
. "$(dirname "$0")/lib.sh"
sql=${1:-}
db=${2:-labapp}
[ -n "$sql" ] || die "usage: scripts/db-admin.sh \"SELECT datname, datacl FROM pg_database\" [database]"

case "$(lab_env)" in
  kind)
    k exec -i statefulset/postgres -c postgres -- psql -U labapp -d "$db" -c "$sql"
    ;;
  aks)
    pod=$(ready_web_pod)
    [ -n "$pod" ] || die "no ready web pod to reach the database through"
    host=$(tf_out postgres_fqdn)
    user=$(tf_out postgres_admin_login)
    tf_out postgres_admin_password | k exec -i "$pod" -c web -- python -c '
import sys, psycopg
host, user, db, sql = sys.argv[1:5]
with psycopg.connect(host=host, dbname=db, user=user, password=sys.stdin.read(),
                     sslmode="require", connect_timeout=10, autocommit=True) as conn:
    cur = conn.execute(sql)
    if cur.description:
        print(" | ".join(col.name for col in cur.description))
        for row in cur.fetchall():
            print(" | ".join(str(v) for v in row))
    else:
        print(cur.statusmessage)' "$host" "$user" "$db" "$sql"
    ;;
esac
